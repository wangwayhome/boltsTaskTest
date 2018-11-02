# Bolts主要源码解析



##关键代码一：bolts的continueWithBlock  如何实现链式调用，与*Masonry*有何区别

####1、Demo层

错误异常取消例子中，上周疑问的地方有的人提出在于 为何 return nil 之后 链式还能继续。

```objective-c
- (IBAction)errorAction:(id)sender {
    [[[[[self findAsync:@"123"] continueWithSuccessBlock:^id(BFTask *task) {
        NSString *resultString= task.result;
        NSLog(@"第一个block resultString = %@",resultString);
        //这里给了个错误
        return [BFTask taskWithError:[NSError errorWithDomain:@"example.com"
                                                         code:-1
                                                     userInfo:nil]];
    }] continueWithSuccessBlock:^id(BFTask *task) {
        // 大家猜一下，然后这个Block会被skipped吗？
        NSString *resultString = task.result;
        NSLog(@"第二个block resultString = %@",resultString);
        return [self findAsync:@"123"];
    }] continueWithBlock:^id(BFTask *task) {
        if (task.error) {
            NSLog(@"出错啦");
            //会进来到这里
            // 错误信息显示如上设置的
            // 在这边可以处理相应的错误信息
            // 返回nil 表示task 执行结束
            return nil;
        }
        // 大家猜一下，这边的代码一样会被skipped吗？
        NSString *resultString = task.result;
        NSLog(@"第三个block resultString = %@",resultString);
        return [self findAsync:@"123"];
    }] continueWithSuccessBlock:^id(BFTask *task) {
        //所有事情做完，这边会被called。
        // 此task 设置返回nil.结束。
        NSLog(@"所有事情做完，这边会被called。此task 设置返回nil.结束");
        return nil;
    }];
}
```

这段代码运行的结果是：

```c
2018-10-27 15:28:45.474841+0800 boltsTaskTest[32044:2983028] 第一个block resultString = 123
2018-10-27 15:28:45.475088+0800 boltsTaskTest[32044:2983028] 出错啦
2018-10-27 15:28:45.475176+0800 boltsTaskTest[32044:2983028] 所有事情做完，这边会被called。此task 设置返回nil.结束
```

####2、SDK层

点进去BFTask类的*ontinueWithSuccessBlock* 或者 *continueWithBlock*  方法里面，我们可以发现，block其实就是一个参数而已，就算block中 return nil，链式照样可以执行。后面会详细分析 continueWithExecutor 如何运作。

```objective-c
- (BFTask *)continueWithBlock:(BFContinuationBlock)block {
    return [self continueWithExecutor:[BFExecutor defaultExecutor] block:block cancellationToken:nil];
}

- (BFTask *)continueWithSuccessBlock:(BFContinuationBlock)block {
    return [self continueWithExecutor:[BFExecutor defaultExecutor] successBlock:block cancellationToken:nil];
}
```

而这个链式反应，跟*Masonry*的 点 就有区别了

![image-20181027155051562](https://ws3.sinaimg.cn/large/006tNbRwly1fwmtz9famdj30vy03sgmn.jpg)

![image-20181027155132677](https://ws4.sinaimg.cn/large/006tNbRwly1fwmtzypxzrj30zw0q8gr5.jpg)

显然得知，大家应该可以清楚的看到二者的区别，如果其中left 或者top 等return nil ，那就无法继续点之后的事情了。



##关键代码二：continueWithExecutor:block:cancellationToken实现 

```objective-c
- (BFTask *)continueWithExecutor:(BFExecutor *)executor
                           block:(BFContinuationBlock)block
               cancellationToken:(nullable BFCancellationToken *)cancellationToken {
    BFTaskCompletionSource *tcs = [BFTaskCompletionSource taskCompletionSource];

    // 捕获BFContinuationBlock完成时的所有状态。
    dispatch_block_t executionBlock = ^{
        if (cancellationToken.cancellationRequested) {//是否被取消
            [tcs cancel];//把tcs 取消
            return;
        }

        id result = block(self);//BFContinuationBlock return的参数
        if ([result isKindOfClass:[BFTask class]]) {//设置和处理task状态

            id (^setupWithTask) (BFTask *) = ^id(BFTask *task) {
                if (cancellationToken.cancellationRequested || task.cancelled) {
                    //判断是否被取消
                    [tcs cancel];
                } else if (task.error) {
                    //判断是否有错误消息
                    tcs.error = task.error;
                } else {
                    //给定正确的结果返回
                    tcs.result = task.result;
                }
                return nil;//完成任务
            };

            BFTask *resultTask = (BFTask *)result;//获取block返回的task

            if (resultTask.completed) {//判断是否完成
                setupWithTask(resultTask);//设置和处理task状态
            } else {
                [resultTask continueWithBlock:setupWithTask];//没有完成，使用continueWithBlock 设置获取结果后应该处理setupWithTask 。递归至setupWithTask 设置 return nil; 进而进入分支id result = block(self);  result = nil; 进而 tcs.result = result;（nil）
            }

        } else {
            tcs.result = result;
        }
    };
//如果self没有completed，executionBlock加入callbacks数组中。在设置result 等地方会对callbacks进行调用。
//callbacks的访问需要加锁
    BOOL completed;
    @synchronized(self.lock) {
        completed = self.completed;
        if (!completed) {
            [self.callbacks addObject:[^{
                [executor execute:executionBlock];
            } copy]];
        }
    }
    if (completed) {
        [executor execute:executionBlock];
    }

    return tcs.task;
}





```

##关键代码三： BFContinuationBlock对result 设置通过trySetResult处理 所有的callbacks。

```objective-c
- (void)setResult:(nullable id)result {

    if (![self.task trySetResult:result]) {

        [NSException raise:NSInternalInconsistencyException

                    format:@"Cannot set the result on a completed task."];

    }

}

- (BOOL)trySetResult:(nullable id)result {
    @synchronized(self.lock) {
        if (self.completed) {
            return NO;
        }
        self.completed = YES;
        _result = result;
        [self runContinuations];
        return YES;
    }
}



- (void)runContinuations {
    @synchronized(self.lock) {
        [self.condition lock];
        [self.condition broadcast];
        [self.condition unlock];
        for (void (^callback)() in self.callbacks) {
            callback();
        }
        [self.callbacks removeAllObjects];
    }
}

```

## 关键代码四：BFTask大佬手下干活的小弟BFExecutor 

这个方法内，国外的程序员真细心。比如说还会先判断系统当前的totalStackSize 和 remainingStackSize ，如果callbackblock 太深的话，会使用GCD的dispatch_get_global_queue，否则是在当前线程执行block。

```objective-c
+ (instancetype)defaultExecutor {
    static BFExecutor *defaultExecutor = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultExecutor = [self executorWithBlock:^void(void(^block)()) {
            // 我们喜欢立即运行所有可能的内容，这样就有了callstack信息
            // 当 debugging. 然而, 我们不希望堆栈变得太深, 如果剩余的堆栈空间
            // 小于总空间的10%，我们分派到另一个GCD队列。
            size_t totalStackSize = 0;
            size_t remainingStackSize = remaining_stack_size(&totalStackSize);

            if (remainingStackSize < (totalStackSize / 10)) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);
            } else {
                @autoreleasepool {
                    block();
                }
            }
        }];
    });
    return defaultExecutor;
}


+ (instancetype)executorWithBlock:(void(^)(void(^block)()))block {
    return [[self alloc] initWithBlock:block];
}

#pragma mark - Initializer
//初始化block
- (instancetype)initWithBlock:(void(^)(void(^block)()))block {
    self = [super init];
    if (!self) return self;

    _block = block;

    return self;
}

#pragma mark - Execution
//上层代码调用对block的传递
- (void)execute:(void(^)())block {
    self.block(block);
}
```

如果不需要用default的设定，当然还有提供很多其他的方式给开发者调用，比如说在主线程调用block，或者需要制定执行某个block，dispatch_queue_t ，NSOperationQueue 等。

```objective-c
/*!
返回一个执行程序，该执行程序在完成前一个任务的线程上运行continuations。
 */
+ (instancetype)immediateExecutor;

/*!
返回在主线程上运行延续的执行程序。
*/
+ (instancetype)mainThreadExecutor;

/*!
返回一个新的执行程序，该执行程序使用给定的块执行延续。
@param block 要使用的块.
 */
+ (instancetype)executorWithBlock:(void(^)(void(^block)()))block;

/*!
 返回在给定队列上运行延续的新执行程序。
 @param queue  `dispatch_queue_t` dispatch的队列
 */
+ (instancetype)executorWithDispatchQueue:(dispatch_queue_t)queue;

/*!
 返回在给定队列上运行延续的新执行程序。
 @param queue NSOperationQueue的队列
 */
+ (instancetype)executorWithOperationQueue:(NSOperationQueue *)queue;

```

remainingStackSize 实现

```objective-c

/*!
获取当前线程的剩余堆栈大小.

 @param totalSize 当前线程的总堆栈大小。

 @return The remaining size, in bytes, 可用于当前线程。

 @note 此函数不能内联inline，否则内部实现可能无法报告正确的剩余的堆栈空间。
 */
__attribute__((noinline)) static size_t remaining_stack_size(size_t *restrict totalSize) {
    pthread_t currentThread = pthread_self();

    // NOTE: 我们必须将堆栈指针存储为uint8_t
    uint8_t *endStack = pthread_get_stackaddr_np(currentThread);
    *totalSize = pthread_get_stacksize_np(currentThread);

    // NOTE: 如果函数是inlined内联的，这个值可能不正确
    uint8_t *frameAddr = __builtin_frame_address(0);

    return (*totalSize) - (size_t)(endStack - frameAddr);
}
```

