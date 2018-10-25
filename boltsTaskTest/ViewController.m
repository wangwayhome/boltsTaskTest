//
//  ViewController.m
//  boltsTaskTest
//
//  Created by wangwayhome on 2017/5/3.
//  Copyright © 2017年 wangwayhome. All rights reserved.
//

#import "ViewController.h"
#import "Bolts.h"

@interface ViewController ()

@property (nonatomic,strong) NSURLSession *session;

@end

@implementation ViewController

#pragma mark - Life Cycle Methods

- (void)viewDidLoad {
    [super viewDidLoad];
    self.session = [NSURLSession sharedSession];
}

#pragma mark - Creating Async Methods

/*
 * 创建一个标示BFTask是否完成的类，BFTaskCompletionSource本身就含有一个BFTask.
 * 在下面的代码中object完成操作后，对taskSource中的task进行设置，标示这个task的完成情况，用于外部对这个task的后续处理。
 */

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

#pragma mark - Button Action Methods

/**
 continueWithblock

 @param sender sender description
 */

- (IBAction)continueWithblockAction:(id)sender {
    
        NSString *obj = @"123";
        
        // Objective-C
        [[self findAsync:obj] continueWithSuccessBlock:^id(BFTask *task) {
            NSLog(@"如果只需要关心成功情况可以使用continueWithSuccessBlock");
            if (task.result) {
                // fetchAsync task 成功
                NSLog(@"task.result = %@",task.result);
            }
            else if (task.error) {
                // fetchAsync task 失败
            }
            
            return nil;
        }];
}

/**
 链式用法

 @param sender sender description
 */

- (IBAction)tasksAction:(id)sender {

    NSLog(@"======链式用法========");
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
    NSLog(@"======链式用法========");
}

/**
 链式用法 取消

 @param sender sender description
 */
- (IBAction)cancelAction:(id)sender {

    BFCancellationTokenSource *cts = [BFCancellationTokenSource cancellationTokenSource];
    
    NSLog(@"======链式用法========");
    [[[[[self reqAsync:1000] continueWithBlock:^id(BFTask *task) {
        NSString *string = [NSString stringWithFormat:@"l1-%@", task.result];
        NSLog(@"%@", string);
        
        return [self reqAsync:1];
    } cancellationToken:cts.token] continueWithBlock:^id(BFTask *task) {
        if (cts.isCancellationRequested) {
            
            return [BFTask cancelledTask];
        }
        NSLog(@"%@",@(cts.isCancellationRequested));
        NSString *string = [NSString stringWithFormat:@"l2-%@", task.result];
        NSLog(@"%@", string);
        
        return [self reqAsync:2];
    }] continueWithBlock:^id(BFTask *task) {
        NSString *string = [NSString stringWithFormat:@"l3-%@", task.result];
        NSLog(@"%@", string);
        
        return [self reqAsync:3];
    }] continueWithBlock:^id(BFTask *task) {
        NSLog(@"Everything is done! %@", task.result);
        
        return nil;
    }];
    NSLog(@"======链式用法========");
    
    [cts cancel];
    
}

/**
 串行任务

 @param sender sender description
 */

- (IBAction)SeriesTasksAction:(id)sender {
//    NSMutableArray *tasks = [NSMutableArray array];
    
    [[[self findAsync:@"123"] continueWithBlock:^id(BFTask *task) {
        
        NSLog(@"===== 串行任务=======");
        // 创建一个开始的任务，之后的每一个reqAsync操作都会依次在这个任务之后顺序进行.
        BFTask *taska = [BFTask taskWithResult:nil];
        
        for (int i=0;i<10;i++) {
            // For each item, extend the task with a function to delete the item.
            taska = [taska continueWithBlock:^id(BFTask *task) {
                // Return a task that will be marked as completed when the delete is finished.
                return [self reqAsync:i];
            }];
//            [tasks addObject:taska];
        }
        
        // 返回的是最后一个reqAsync操作的task
        return taska;
        
    }] continueWithBlock:^id(BFTask *task) {
        NSLog(@"last task : %@",task);
        // Every comment was deleted.
//        for (BFTask *taska in tasks ) {
//            NSLog(@"taska : %@",taska);
//        }
        NSLog(@"Every comment was deleted.");
        NSLog(@"===== 串行任务=======");
        
        return task;
        
    }];
}

/**
 并行任务

 @param sender sender description
 */

- (IBAction)ParallelAction:(id)sender {
    NSMutableArray *tasks = [NSMutableArray array];
    
    [[[self reqAsync:1000] continueWithBlock:^id(BFTask *task) {
        NSLog(@"=====并行任务=======");
        
        for (int i=0;i<10;i++) {
            // For each item, extend the task with a function to delete the item.
            // Return a task that will be marked as completed when the delete is finished.
            [tasks addObject:[self reqAsync:i]];
        }
        
        // 所有的删除任务合在一起本身也是一个任务，删除任务之前是并行的
        return [BFTask taskForCompletionOfAllTasks:tasks];
    }]continueWithBlock:^id(BFTask *task) {
        // Every comment was deleted.
//        for (BFTask *taska in tasks ) {
//            NSLog(@"taska : %@",taska.result);
//        }
        NSLog(@"Every comment was deleted.");
        NSLog(@"=====并行任务=======");
        return task;
    }];
    
}

@end
