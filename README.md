



## Bolts介绍

GitHub地址： https://github.com/BoltsFramework/Bolts-ObjC

Bolts is a collection of low-level libraries designed to make developing mobile apps easier. Bolts was designed by Parse and Facebook for our own internal use, and we have decided to open source these libraries to make them available to others. Using these libraries does not require using any Parse services. Nor do they require having a Parse or Facebook developer account.

Bolts includes:

- "Tasks", which make organization of complex asynchronous code more manageable. A task is kind of like a JavaScript Promise, but available for iOS and Android.
- An implementation of the [App Links protocol](http://applinks.org/), helping you link to content in other apps and handle incoming deep-links.

For more information, see the [Bolts iOS API Reference](http://boltsframework.github.io/docs/ios/).

![img](https://ws1.sinaimg.cn/large/006tNbRwly1fwj9gkat1lj308c08c74e.jpg)

 什么，一堆英文，你能不能说拆尼厮呢？

好。。。以下翻译：

Bolts是一个为了方便移动APP开发而设计的低级库集合。Bolts由Parse和Facebook设计用来我们内部使用的，现在我们决定开源这些库让其他人也可以用。使用这些库不需要添加使用任何Parse的服务，也不需要拥有一个Parse或者Facebook的开发者账号。

Bolts包含：

- “Tasks”,它使得复杂的异步代码更易于管理。一个任务类似于JavaScript的Promise，但是它可以用于ios和Android。
- 一个[App Links protocol](http://www.applinks.org/)的实现，帮助您链接到其他应用程序中的内容，并处理传入的多层链接。



说了这么多介绍有啥用，重点呢？然后呢？

来了～![img](https://ws4.sinaimg.cn/large/006tNbRwly1fwj9iz9lixj30ao0c6dgc.jpg)

接下来跟大家分享一下Bolts



## The `continueWithBlock` Method

每个`BFTask`都有一个 `continueWithBlock:` 方法   顾名思义，就是`BFTask`完成之后进入此block。

你可以在这个block里面去check 是否成功并且去获取result信息。

```objective-c
[[self saveAsync:obj] continueWithBlock:^id(BFTask *task) {//创建一个saveAsync异步方法
  if (task.isCancelled) {
    // 这个save任务被取消了
  } else if (task.error) {
    // 这个save任务发生错误
  } else {
    // 这个obj被保存成功
    PFObject *object = task.result;
  }
  return nil;
}];
```



在很多时候,你可能只需要获取task成功的回调用来继续下一件任务可以用 `continueWithSuccessBlock:` 方法来替代 `continueWithBlock:`. 

```objective-c
[[self saveAsync:obj] continueWithSuccessBlock:^id(BFTask *task) {
  // 当这个task成功完成.
  return nil;
}];
```



## Chaining Tasks Together 链式用法

BFTasks有点神奇的是 因为它们可以让你在没有嵌套的情况下链式的使用它们。 

以往我们使用block 跟盖金字塔式的代码一个堆一个上去。

例如：

![img](https://ws1.sinaimg.cn/large/006tNbRwly1fwkj5ixn8ej308c08c3yn.jpg)

```objective-c
    @weakify(self);
    [self request4sPartnerRebateCountQueryCompletionBlock:^(NSError *error) {
        @strongify(self);
        if (!error) {
            [self requestLoanPartnerRebateCountQueryCompletionBlock:^(NSError *error) {
                if (block) {
                    block(error);
                }
            }];
        } else {
            if (block) {
                block(error);
            }
        }
    }];
```



现在有了全新的方式，漂移的骚操作来了

![img](https://ws1.sinaimg.cn/large/006tNbRwly1fwkj64is4wj308c08c74g.jpg)

如果从continueWithBlock：返回BFTask，则continueWithBlock：返回的任务将不会被视为已完成，直到新任务从新的continuation block返回。 这使您可以执行多个操作，而不会产生回调所带来的金字塔代码。 同样，您可以从continueWithSuccessBlock返回BFTask：。 所以，返回一个BFTask来做更多的异步工作。

```objective-c
    [[[[[self reqAsync:1000] continueWithSuccessBlock:^id(BFTask *task) {
        NSString *string = [NSString stringWithFormat:@"l1-%@", task.result];
        NSLog(@"%@", string);
        
        return [self reqAsync:1];
    }] continueWithSuccessBlock:^id(BFTask *task) {
        NSString *string = [NSString stringWithFormat:@"l2-%@", task.result];
        NSLog(@"%@", string);
        
        return [self reqAsync:2];
    }] continueWithSuccessBlock:^id(BFTask *task) {
        NSString *string = [NSString stringWithFormat:@"l3-%@", task.result];
        NSLog(@"%@", string);
        
        return [self reqAsync:3];
    }] continueWithSuccessBlock:^id(BFTask *task) {
        
        NSLog(@"Everything is done! %@", task.result);
        return nil;
    }];
```



## Error Handling

 要谨慎使用 `continueWithBlock:` or `continueWithSuccessBlock:`,  用了 `continueWithBlock:` 你可以处理错误消息，你可以把失败的任务想成是抛出一个异常。

```objective-c
[[[[[self findAsync:query] continueWithSuccessBlock:^id(BFTask *task) {
  NSArray *students = task.result;
  PFObject *valedictorian = [students objectAtIndex:0];
  [valedictorian setObject:@YES forKey:@"valedictorian"];
  //这里给了个错误
  return [BFTask taskWithError:[NSError errorWithDomain:@"example.com"
                                                   code:-1
                                               userInfo:nil]];
}] continueWithSuccessBlock:^id(BFTask *task) {
  // 大家猜一下，然后这个Block会被skipped吗？
  PFQuery *valedictorian = task.result;
  return [self findAsync:query];
}] continueWithBlock:^id(BFTask *task) {
  if (task.error) {
    //会进来到这里
    // 错误信息显示如上设置的
    // 在这边可以处理相应的错误信息
    // 返回nil 表示task 执行结束
    return nil;
  }
  // 大家猜一下，这边的代码一样会被skipped吗？
  NSArray *students = task.result;
  PFObject *salutatorian = [students objectAtIndex:1];
  [salutatorian setObject:@YES forKey:@"salutatorian"];
  return [self saveAsync:salutatorian];
}] continueWithSuccessBlock:^id(BFTask *task) {
  //所有事情做完，这边会被called。
  // 此task 设置返回nil.结束。
  return nil;
}];
```

通常情况下，在一个很长的成功回调链里，我们选择在最后给一个错误处理，这样看起来代码会很清爽简洁。



## Creating Tasks



 * 创建一个标示BFTask是否完成的类，BFTaskCompletionSource本身就含有一个BFTask.
 * 在下面的代码中object完成操作后,比如网络请求 ，对taskSource中的task进行设置，标示这个task的完成情况，用于外部对这个task的后续处理。
    ​

```objective-c


- (BFTask *) findAsync:(NSString *)object {

    BFTaskCompletionSource *taskSource = [BFTaskCompletionSource taskCompletionSource];
    
    [taskSource setResult:object];
    
    return taskSource.task;
}

- (BFTask *) reqAsync:(int)index {
    
    BFTaskCompletionSource *taskSource = [BFTaskCompletionSource taskCompletionSource];
    
    NSURL *url = [NSURL URLWithString:@"https://news.baidu.com/"];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    NSURLSessionDataTask *dataTask = [_session dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            [taskSource setError:error];
        } else {
            NSHTTPURLResponse  *ss = (NSHTTPURLResponse *)response;
            NSLog(@"index i= %d response statusCode = %@",index,@(ss.statusCode));
            NSString *str = [NSString stringWithFormat:@"index i= %d response statusCode = %@",index,@(ss.statusCode)];
            [taskSource setResult:str];
        }
    }];
    
    [dataTask resume];
    
    
    return taskSource.task;
}
```



## Tasks in Series

同步操作，一个task任务做完之后再继续下一个，比如评论区删除全部评论的场景。

```objective-c
 [[[self findAsync:@"123"] continueWithBlock:^id(BFTask *task) {
     // 创建一个开始的任务，之后的每一个reqAsync操作都会依次在这个任务之后顺序进行.
        BFTask *taska = [BFTask taskWithResult:nil];
        
        for (int i=0;i<10;i++) {
            // For each item, extend the task with a function to delete the item.
            taska = [taska continueWithBlock:^id(BFTask *task) {
                // Return a task that will be marked as completed when the delete is finished.
                return [self reqAsync:i];
            }];
        }
        
        // 返回的是最后一个reqAsync操作的task
        return taska;
        
    }] continueWithBlock:^id(BFTask *task) {
        NSLog(@"任务都完成了.");        
        return task;
        
    }];
```



## Tasks in Parallel

异步操作，开始所有的异步任务，创建 `taskForCompletionOfAllTasks:` 任务之后，会标记所有任务执行完，进入成回调。

```objective-c
  [[[self reqAsync:1000] continueWithBlock:^id(BFTask *task) {    
        for (int i=0;i<10;i++) {
            [tasks addObject:[self reqAsync:i]];
        }  
        return [BFTask taskForCompletionOfAllTasks:tasks];
    }]continueWithBlock:^id(BFTask *task) {
        NSLog(@"所有任务完成.");
        return task;
    }];
```



## 取消任务

跟踪 `BFTaskCompletionSource` 的取消是不好的设计，更好的模型是在顶层创建一个"cancellation token" ，并且通过取消的token令牌在block里监听是否取消等后续操作。

```objective-c
   BFCancellationTokenSource *cts = [BFCancellationTokenSource cancellationTokenSource];
    
    [[[self reqAsync:1000] continueWithBlock:^id(BFTask *task) {
        NSString *string = [NSString stringWithFormat:@"l1000-%@", task.result];
        NSLog(@"%@", string);

        return [self reqAsync:1];
    } cancellationToken:cts.token] continueWithBlock:^id(BFTask *task) {
        
        if (cts.isCancellationRequested) {
            NSLog(@"线程取消");
            
            return [BFTask cancelledTask];
        }
        
        NSLog(@"%@",@(cts.isCancellationRequested));
        NSString *string = [NSString stringWithFormat:@"l1-%@", task.result];
        NSLog(@"%@", string);
        
        return nil;
    }];
    
    
    
    dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC));
    
    dispatch_after(delayTime, dispatch_get_main_queue(), ^{

        [cts cancel];
        
    });
```
