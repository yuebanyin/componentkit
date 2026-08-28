/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <XCTest/XCTest.h>

#import <ComponentTextKit/CKAsyncTransaction.h>
#import <ComponentTextKit/CKAsyncTransactionContainer+Private.h>
#import <ComponentTextKit/CKAsyncTransactionContainer.h>
#import <ComponentTextKit/CKAsyncTransactionGroup.h>

@interface CKAsyncTransactionGroup (CKAsyncTransactionContainerTests)
- (void)commit;
@end

@interface CKAsyncTransactionTestLayer : CALayer
@property (nonatomic, strong) NSMutableArray<NSNumber *> *stateChanges;
@end

@implementation CKAsyncTransactionTestLayer

- (instancetype)init
{
  if (self = [super init]) {
    _stateChanges = [NSMutableArray array];
  }
  return self;
}

- (void)ck_asyncTransactionContainerStateDidChange
{
  [_stateChanges addObject:@(self.ck_asyncTransactionContainerState)];
}

@end

@interface CKAsyncTransactionTestView : UIView
@property (nonatomic, strong) NSMutableArray<NSNumber *> *stateChanges;
@end

@implementation CKAsyncTransactionTestView

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    _stateChanges = [NSMutableArray array];
  }
  return self;
}

- (void)ck_asyncTransactionContainerStateDidChange
{
  [_stateChanges addObject:@(self.ck_asyncTransactionContainerState)];
}

@end

@interface CKAsyncTransactionContainerTests : XCTestCase
@end

@implementation CKAsyncTransactionContainerTests

- (void)testStateRemainsPendingUntilAllOverlappingTransactionsComplete
{
  CKAsyncTransactionTestLayer *layer = [[CKAsyncTransactionTestLayer alloc] init];
  XCTAssertEqual(layer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStateNoTransactions);
  XCTAssertEqual(layer.stateChanges.count, 0u);

  dispatch_queue_t firstQueue = dispatch_queue_create("org.componentkit.async-transaction.first", DISPATCH_QUEUE_SERIAL);
  dispatch_queue_t secondQueue = dispatch_queue_create("org.componentkit.async-transaction.second", DISPATCH_QUEUE_SERIAL);
  dispatch_suspend(firstQueue);
  dispatch_suspend(secondQueue);

  XCTestExpectation *firstCompletion = [self expectationWithDescription:@"first transaction completed"];
  __block BOOL firstCanceled = YES;
  CKAsyncTransaction *firstTransaction = layer.ck_asyncTransaction;
  [firstTransaction addOperationWithBlock:^id<NSObject> {
    return @"first";
  } queue:firstQueue completion:^(id<NSObject> value, BOOL canceled) {
    XCTAssertTrue([NSThread isMainThread]);
    XCTAssertEqualObjects(value, @"first");
    firstCanceled = canceled;
    // The container removes a transaction after its operation completions run.
    // Check container state on the following callback-queue turn.
    dispatch_async(dispatch_get_main_queue(), ^{
      [firstCompletion fulfill];
    });
  }];
  XCTAssertEqual(layer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStatePendingTransactions);
  XCTAssertEqualObjects(layer.stateChanges, (@[@(CKAsyncTransactionContainerStatePendingTransactions)]));

  [[CKAsyncTransactionGroup mainTransactionGroup] commit];
  XCTAssertEqual(firstTransaction.state, CKAsyncTransactionStateCommitted);

  __block XCTestExpectation *secondCompletion = nil;
  __block BOOL secondCanceled = YES;
  CKAsyncTransaction *secondTransaction = layer.ck_asyncTransaction;
  XCTAssertTrue(firstTransaction != secondTransaction);
  [secondTransaction addOperationWithBlock:^id<NSObject> {
    return @"second";
  } queue:secondQueue completion:^(id<NSObject> value, BOOL canceled) {
    XCTAssertTrue([NSThread isMainThread]);
    XCTAssertEqualObjects(value, @"second");
    secondCanceled = canceled;
    dispatch_async(dispatch_get_main_queue(), ^{
      [secondCompletion fulfill];
    });
  }];
  [[CKAsyncTransactionGroup mainTransactionGroup] commit];

  XCTAssertEqual(secondTransaction.state, CKAsyncTransactionStateCommitted);
  XCTAssertEqual(layer.ck_asyncLayerTransactions.count, 2u);
  XCTAssertEqual(layer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStatePendingTransactions);
  XCTAssertEqualObjects(layer.stateChanges, (@[@(CKAsyncTransactionContainerStatePendingTransactions)]));

  dispatch_resume(firstQueue);
  [self waitForExpectationsWithTimeout:5 handler:nil];

  XCTAssertFalse(firstCanceled);
  XCTAssertEqual(layer.ck_asyncLayerTransactions.count, 1u);
  XCTAssertEqual(layer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStatePendingTransactions);
  XCTAssertEqualObjects(layer.stateChanges, (@[@(CKAsyncTransactionContainerStatePendingTransactions)]));

  secondCompletion = [self expectationWithDescription:@"second transaction completed"];
  dispatch_resume(secondQueue);
  [self waitForExpectationsWithTimeout:5 handler:nil];

  XCTAssertFalse(secondCanceled);
  XCTAssertEqual(layer.ck_asyncLayerTransactions.count, 0u);
  XCTAssertEqual(layer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStateNoTransactions);
  XCTAssertEqualObjects(layer.stateChanges, (@[
    @(CKAsyncTransactionContainerStatePendingTransactions),
    @(CKAsyncTransactionContainerStateNoTransactions),
  ]));
}

- (void)testCancelCancelsCurrentAndCommittedTransactionsAndCallbacksReportCancellation
{
  CKAsyncTransactionTestLayer *layer = [[CKAsyncTransactionTestLayer alloc] init];
  dispatch_queue_t committedQueue = dispatch_queue_create("org.componentkit.async-transaction.committed", DISPATCH_QUEUE_SERIAL);
  dispatch_queue_t currentQueue = dispatch_queue_create("org.componentkit.async-transaction.current", DISPATCH_QUEUE_SERIAL);
  dispatch_suspend(committedQueue);
  dispatch_suspend(currentQueue);

  XCTestExpectation *committedCompletion = [self expectationWithDescription:@"committed transaction canceled"];
  XCTestExpectation *currentCompletion = [self expectationWithDescription:@"current transaction canceled"];
  __block BOOL committedCallbackCanceled = NO;
  __block BOOL currentCallbackCanceled = NO;

  CKAsyncTransaction *committedTransaction = layer.ck_asyncTransaction;
  [committedTransaction addOperationWithBlock:^id<NSObject> {
    return @"must not execute";
  } queue:committedQueue completion:^(id<NSObject> value, BOOL canceled) {
    XCTAssertTrue([NSThread isMainThread]);
    XCTAssertNil(value);
    committedCallbackCanceled = canceled;
    dispatch_async(dispatch_get_main_queue(), ^{
      [committedCompletion fulfill];
    });
  }];
  [[CKAsyncTransactionGroup mainTransactionGroup] commit];

  CKAsyncTransaction *currentTransaction = layer.ck_asyncTransaction;
  [currentTransaction addOperationWithBlock:^id<NSObject> {
    return @"must not execute";
  } queue:currentQueue completion:^(id<NSObject> value, BOOL canceled) {
    XCTAssertTrue([NSThread isMainThread]);
    XCTAssertNil(value);
    currentCallbackCanceled = canceled;
    dispatch_async(dispatch_get_main_queue(), ^{
      [currentCompletion fulfill];
    });
  }];

  XCTAssertTrue(committedTransaction.callbackQueue == dispatch_get_main_queue());
  XCTAssertTrue(currentTransaction.callbackQueue == dispatch_get_main_queue());
  XCTAssertEqual(committedTransaction.state, CKAsyncTransactionStateCommitted);
  XCTAssertEqual(currentTransaction.state, CKAsyncTransactionStateOpen);
  XCTAssertEqual(layer.ck_asyncLayerTransactions.count, 2u);

  [layer ck_cancelAsyncTransactions];

  XCTAssertEqual(committedTransaction.state, CKAsyncTransactionStateCanceled);
  XCTAssertEqual(currentTransaction.state, CKAsyncTransactionStateCanceled);
  XCTAssertNil(layer.ck_currentAsyncLayerTransaction);
  XCTAssertEqual(layer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStatePendingTransactions);
  XCTAssertEqualObjects(layer.stateChanges, (@[@(CKAsyncTransactionContainerStatePendingTransactions)]));

  dispatch_resume(committedQueue);
  dispatch_resume(currentQueue);
  [self waitForExpectationsWithTimeout:5 handler:nil];

  XCTAssertTrue(committedCallbackCanceled);
  XCTAssertTrue(currentCallbackCanceled);
  XCTAssertEqual(layer.ck_asyncLayerTransactions.count, 0u);
  XCTAssertEqual(layer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStateNoTransactions);
  XCTAssertEqualObjects(layer.stateChanges, (@[
    @(CKAsyncTransactionContainerStatePendingTransactions),
    @(CKAsyncTransactionContainerStateNoTransactions),
  ]));
}

- (void)testTrackingAndCancellationAreIsolatedBetweenLayers
{
  CKAsyncTransactionTestLayer *firstLayer = [[CKAsyncTransactionTestLayer alloc] init];
  CKAsyncTransactionTestLayer *secondLayer = [[CKAsyncTransactionTestLayer alloc] init];
  dispatch_queue_t firstQueue = dispatch_queue_create("org.componentkit.async-transaction.layer-one", DISPATCH_QUEUE_SERIAL);
  dispatch_queue_t secondQueue = dispatch_queue_create("org.componentkit.async-transaction.layer-two", DISPATCH_QUEUE_SERIAL);
  dispatch_suspend(firstQueue);
  dispatch_suspend(secondQueue);

  XCTestExpectation *firstCompletion = [self expectationWithDescription:@"first layer canceled"];
  __block XCTestExpectation *secondCompletion = nil;
  __block BOOL firstCanceled = NO;
  __block BOOL secondCanceled = YES;

  CKAsyncTransaction *firstTransaction = firstLayer.ck_asyncTransaction;
  [firstTransaction addOperationWithBlock:^id<NSObject> {
    return @"must not execute";
  } queue:firstQueue completion:^(id<NSObject> value, BOOL canceled) {
    XCTAssertTrue([NSThread isMainThread]);
    XCTAssertNil(value);
    firstCanceled = canceled;
    dispatch_async(dispatch_get_main_queue(), ^{
      [firstCompletion fulfill];
    });
  }];
  [[CKAsyncTransactionGroup mainTransactionGroup] commit];

  CKAsyncTransaction *secondTransaction = secondLayer.ck_asyncTransaction;
  [secondTransaction addOperationWithBlock:^id<NSObject> {
    return @"second layer";
  } queue:secondQueue completion:^(id<NSObject> value, BOOL canceled) {
    XCTAssertTrue([NSThread isMainThread]);
    XCTAssertEqualObjects(value, @"second layer");
    secondCanceled = canceled;
    dispatch_async(dispatch_get_main_queue(), ^{
      [secondCompletion fulfill];
    });
  }];

  XCTAssertTrue(firstLayer.ck_asyncLayerTransactions != secondLayer.ck_asyncLayerTransactions);
  XCTAssertEqual(firstLayer.ck_asyncLayerTransactions.count, 1u);
  XCTAssertEqual(secondLayer.ck_asyncLayerTransactions.count, 1u);

  [firstLayer ck_cancelAsyncTransactions];

  XCTAssertEqual(firstTransaction.state, CKAsyncTransactionStateCanceled);
  XCTAssertEqual(secondTransaction.state, CKAsyncTransactionStateOpen);
  XCTAssertTrue(secondLayer.ck_currentAsyncLayerTransaction == secondTransaction);
  XCTAssertEqual(secondLayer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStatePendingTransactions);

  [[CKAsyncTransactionGroup mainTransactionGroup] commit];
  XCTAssertEqual(secondTransaction.state, CKAsyncTransactionStateCommitted);

  dispatch_resume(firstQueue);
  [self waitForExpectationsWithTimeout:5 handler:nil];

  XCTAssertTrue(firstCanceled);
  XCTAssertEqual(firstLayer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStateNoTransactions);
  XCTAssertEqual(secondLayer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStatePendingTransactions);
  XCTAssertEqualObjects(firstLayer.stateChanges, (@[
    @(CKAsyncTransactionContainerStatePendingTransactions),
    @(CKAsyncTransactionContainerStateNoTransactions),
  ]));
  XCTAssertEqualObjects(secondLayer.stateChanges, (@[@(CKAsyncTransactionContainerStatePendingTransactions)]));

  secondCompletion = [self expectationWithDescription:@"second layer completed"];
  dispatch_resume(secondQueue);
  [self waitForExpectationsWithTimeout:5 handler:nil];

  XCTAssertFalse(secondCanceled);
  XCTAssertEqual(secondLayer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStateNoTransactions);
  XCTAssertEqualObjects(secondLayer.stateChanges, (@[
    @(CKAsyncTransactionContainerStatePendingTransactions),
    @(CKAsyncTransactionContainerStateNoTransactions),
  ]));
}

- (void)testMainTransactionGroupCoalescesTransactionsUntilCommit
{
  CKAsyncTransactionTestLayer *layer = [[CKAsyncTransactionTestLayer alloc] init];

  CKAsyncTransaction *firstTransaction = layer.ck_asyncTransaction;
  CKAsyncTransaction *coalescedTransaction = layer.ck_asyncTransaction;

  XCTAssertTrue(firstTransaction == coalescedTransaction);
  XCTAssertEqual(layer.ck_asyncLayerTransactions.count, 1u);
  XCTAssertEqualObjects(layer.stateChanges, (@[@(CKAsyncTransactionContainerStatePendingTransactions)]));

  [[CKAsyncTransactionGroup mainTransactionGroup] commit];

  XCTAssertEqual(firstTransaction.state, CKAsyncTransactionStateCommitted);
  XCTAssertNil(layer.ck_currentAsyncLayerTransaction);
  XCTAssertEqual(layer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStateNoTransactions);

  CKAsyncTransaction *nextTransaction = layer.ck_asyncTransaction;
  XCTAssertTrue(firstTransaction != nextTransaction);
  [[CKAsyncTransactionGroup mainTransactionGroup] commit];

  XCTAssertEqual(nextTransaction.state, CKAsyncTransactionStateCommitted);
  XCTAssertEqual(layer.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStateNoTransactions);
  XCTAssertEqualObjects(layer.stateChanges, (@[
    @(CKAsyncTransactionContainerStatePendingTransactions),
    @(CKAsyncTransactionContainerStateNoTransactions),
    @(CKAsyncTransactionContainerStatePendingTransactions),
    @(CKAsyncTransactionContainerStateNoTransactions),
  ]));
}

- (void)testUIViewForwardsContainerStateAndCancellationToItsLayer
{
  CKAsyncTransactionTestView *view = [[CKAsyncTransactionTestView alloc] initWithFrame:CGRectZero];
  [view ck_setAsyncTransactionContainer:YES];
  XCTAssertTrue(view.ck_isAsyncTransactionContainer);
  XCTAssertTrue(view.layer.ck_isAsyncTransactionContainer);
  XCTAssertEqual(view.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStateNoTransactions);

  dispatch_queue_t queue = dispatch_queue_create("org.componentkit.async-transaction.view", DISPATCH_QUEUE_SERIAL);
  dispatch_suspend(queue);
  XCTestExpectation *completion = [self expectationWithDescription:@"view transaction canceled"];
  __block BOOL callbackCanceled = NO;

  CKAsyncTransaction *transaction = view.layer.ck_asyncTransaction;
  [transaction addOperationWithBlock:^id<NSObject> {
    return @"must not execute";
  } queue:queue completion:^(id<NSObject> value, BOOL canceled) {
    XCTAssertTrue([NSThread isMainThread]);
    XCTAssertNil(value);
    callbackCanceled = canceled;
    dispatch_async(dispatch_get_main_queue(), ^{
      [completion fulfill];
    });
  }];

  XCTAssertEqual(view.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStatePendingTransactions);
  XCTAssertEqualObjects(view.stateChanges, (@[@(CKAsyncTransactionContainerStatePendingTransactions)]));

  [view ck_cancelAsyncTransactions];

  XCTAssertEqual(transaction.state, CKAsyncTransactionStateCanceled);
  XCTAssertNil(view.layer.ck_currentAsyncLayerTransaction);
  dispatch_resume(queue);
  [self waitForExpectationsWithTimeout:5 handler:nil];

  XCTAssertTrue(callbackCanceled);
  XCTAssertEqual(view.ck_asyncTransactionContainerState, CKAsyncTransactionContainerStateNoTransactions);
  XCTAssertEqualObjects(view.stateChanges, (@[
    @(CKAsyncTransactionContainerStatePendingTransactions),
    @(CKAsyncTransactionContainerStateNoTransactions),
  ]));

  [view ck_setAsyncTransactionContainer:NO];
  XCTAssertFalse(view.ck_isAsyncTransactionContainer);
  XCTAssertFalse(view.layer.ck_isAsyncTransactionContainer);
}

@end
