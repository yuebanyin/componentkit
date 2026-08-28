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

#import <ComponentKit/CKBuildComponent.h>
#import <ComponentKit/CKComponentScopeRoot.h>
#import <ComponentKit/CKComponentScopeRootFactory.h>
#import <ComponentKit/CKFlexboxComponent.h>
#import <ComponentKit/CKComponent.h>
#import <ComponentKit/CKCompositeComponent.h>
#import <ComponentKit/CKRenderComponent.h>
#import <ComponentKit/CKLayoutComponent.h>
#import <ComponentKit/CKRootTreeNode.h>
#import <ComponentKit/CKComponentInternal.h>
#import <ComponentKit/CKButtonComponent.h>
#import <ComponentKit/CKThreadLocalComponentScope.h>
#import <ComponentKit/CKBuildComponent.h>

#import "CKComponentTestCase.h"

static BOOL verifyChildToParentConnection(CKTreeNode *parentNode, CKTreeNode *childNode, id<CKRenderComponentProtocol> c) {
  auto const componentKey = [childNode componentKey];
  auto const childComponent = [parentNode childForComponentKey:componentKey].component;
  return [childComponent isEqual:c];
}

static NSMutableArray<CKTreeNode*> *createsNodesForComponentsWithOwner(CKTreeNode *owner,
                                                                       CKTreeNode *previousParent,
                                                                       CKComponentScopeRoot *scopeRoot,
                                                                       NSArray<id<CKRenderComponentProtocol>> *components) {
  NSMutableArray<CKTreeNode*> *nodes = [NSMutableArray array];
  for (id<CKRenderComponentProtocol> component in components) {
    CKTreeNode *childNode = [CKTreeNode childPairForComponent:component
                                                       parent:owner
                                               previousParent:previousParent
                                                   scopeRoot:scopeRoot
                                                 stateUpdates:{}].node;

    [nodes addObject:childNode];
  }
  return nodes;
}

/** Iterate recursively over the tree and add its node identifiers to the set */
static void treeChildrenIdentifiers(CKTreeNode *node, NSMutableSet<NSString *> *identifiers, int level) {
  for (auto childNode : node.children) {
    // We add the child identifier + its level in the tree.
    [identifiers addObject:[NSString stringWithFormat:@"%d-%d",childNode.nodeIdentifier, level]];
    treeChildrenIdentifiers(childNode, identifiers, level+1);
  }
}

/** Compare the children of the trees recursively; returns true if the two trees are equal */
static BOOL areTreesEqual(CKTreeNode *lhs, CKTreeNode *rhs) {
  NSMutableSet<NSString *> *lhsChildrenIdentifiers = [NSMutableSet set];
  treeChildrenIdentifiers(lhs, lhsChildrenIdentifiers, 0);
  NSMutableSet<NSString *> *rhsChildrenIdentifiers = [NSMutableSet set];
  treeChildrenIdentifiers(rhs, rhsChildrenIdentifiers, 0);
  return [lhsChildrenIdentifiers isEqualToSet:rhsChildrenIdentifiers];
}

static CKComponent* buildComponent(CKComponent*(^block)()) {
  __block CKComponent *c;
  CKBuildComponent(CKComponentScopeRootWithDefaultPredicates(nil, nil), {}, ^CKComponent *{
    c = block();
    return c;
  });
  return c;
}

@interface CKTreeNodeTest_Component_WithScope : CKComponent
@end

@interface CKTreeNodeTest_RenderComponent_WithChild : CKRenderComponent
{
  CKComponent *_childComponent;
}
+ (instancetype)newWithComponent:(CKComponent *)component;
@end

@interface CKTreeNodeTest_RenderComponent_NoInitialState : CKRenderComponent
@end

@interface CKTreeNodeTest_Component_WithState : CKComponent
@end

@interface CKTreeNodeTest_RenderComponent_WithState : CKRenderComponent
@end

@interface CKTreeNodeTest_RenderComponent_WithStateFromProps : CKRenderComponent
+ (instancetype)newWithProp:(id)prop;
@end

@interface CKTreeNodeTest_RenderComponent_WithNilState : CKRenderComponent
@end

@interface CKTreeNodeTest_RenderComponent_WithIdentifier : CKRenderComponent
+ (instancetype)newWithIdentifier:(id<NSObject>)identifier;
@end

@interface CKTreeNodeTest_CountingIdentifier : NSObject
+ (instancetype)newWithValue:(NSUInteger)value hash:(NSUInteger)hash;
+ (void)resetEqualityComparisons;
+ (NSUInteger)equalityComparisons;
@end

@interface CKTreeNodeTests : CKComponentTestCase
@end

@implementation CKTreeNodeTests

#pragma mark - CKTreeNodeWithChildren

- (void)test_childForComponentKey_onCKTreeNodeWithChildren_withChild {
  // Simulate first component tree creation
  auto const scopeRoot = CKComponentScopeRootWithDefaultPredicates(nil, nil);
  auto const root1 = [CKTreeNode rootNode];
  auto const component1 = [CKTreeNodeTest_RenderComponent_NoInitialState new];
  CKTreeNode *childNode1 = [CKTreeNode childPairForComponent:component1
                                                      parent:root1
                                              previousParent:nil
                                                   scopeRoot:scopeRoot
                                                stateUpdates:{}].node;

  // Simulate a component tree creation due to a state update
  auto const root2 = [CKTreeNode rootNode];
  auto const component2 = [CKTreeNodeTest_RenderComponent_NoInitialState new];
  CKTreeNode *childNode2 = [CKTreeNode childPairForComponent:component2
                                                      parent:root2
                                              previousParent:root1
                                                   scopeRoot:[scopeRoot newRoot]
                                                stateUpdates:{}].node;

  XCTAssertTrue(verifyChildToParentConnection(root1, childNode1, component1));
  XCTAssertTrue(verifyChildToParentConnection(root2, childNode2, component2));
}

- (void)test_nodeIdentifier_onCKTreeNodeWithChildren_betweenGenerations_withChild {
  // Simulate first component tree creation
  auto const scopeRoot = CKComponentScopeRootWithDefaultPredicates(nil, nil);
  auto const root1 = [CKTreeNode rootNode];
  auto const component1 = [CKTreeNodeTest_RenderComponent_NoInitialState new];
  CKTreeNode *childNode1 = [CKTreeNode childPairForComponent:component1
                                                      parent:root1
                                              previousParent:nil
                                                   scopeRoot:scopeRoot
                                                stateUpdates:{}].node;

  // Simulate a component tree creation due to a state update
  auto const root2 = [CKTreeNode rootNode];
  auto const component2 = [CKTreeNodeTest_RenderComponent_NoInitialState new];
  CKTreeNode *childNode2 = [CKTreeNode childPairForComponent:component2
                                                      parent:root2
                                              previousParent:root1
                                                   scopeRoot:[scopeRoot newRoot]
                                                stateUpdates:{}].node;

  XCTAssertEqual(childNode1.nodeIdentifier, childNode2.nodeIdentifier);
}


- (void)test_childForComponentKey_onCKTreeNodeWithChildren_withMultipleChildren {
  auto const scopeRoot = CKComponentScopeRootWithDefaultPredicates(nil, nil);
  auto const root = [CKTreeNode rootNode];

  // Create 4 children components
  NSArray<id<CKRenderComponentProtocol>> *components = @[[CKTreeNodeTest_RenderComponent_NoInitialState new],
                                                         [CKTreeNodeTest_RenderComponent_NoInitialState new],
                                                         [CKTreeNodeTest_RenderComponent_WithState new],
                                                         [CKTreeNodeTest_RenderComponent_NoInitialState new]];

  // Create a childNode for each.
  NSMutableArray<CKTreeNode*> *nodes = createsNodesForComponentsWithOwner(root, nil, scopeRoot, components);

  // Make sure the connections between the parent to the child nodes are correct
  for (NSUInteger i=0; i<components.count; i++) {
    CKTreeNode *childNode = nodes[i];
    auto const component = components[i];
    XCTAssertTrue(verifyChildToParentConnection(root, childNode, component));
  }

  // Create 4 children components
  auto const root2 = [CKTreeNode rootNode];
  NSArray<id<CKRenderComponentProtocol>> *components2 = @[[CKTreeNodeTest_RenderComponent_NoInitialState new],
                                                          [CKTreeNodeTest_RenderComponent_NoInitialState new],
                                                          [CKTreeNodeTest_RenderComponent_WithState new],
                                                          [CKTreeNodeTest_RenderComponent_NoInitialState new]];

  __unused NSMutableArray<CKTreeNode*> *nodes2 = createsNodesForComponentsWithOwner(root2, root, [scopeRoot newRoot], components2);

  // Verify that the two trees are equal.
  XCTAssertTrue(areTreesEqual(root, root2));
}

- (void)test_childForComponentKey_onCKTreeNodeWithChildren_withDifferentChildOverGenerations
{
  // Simulate first component tree creation
  auto const scopeRoot = CKComponentScopeRootWithDefaultPredicates(nil, nil);
  auto const root1 = [CKTreeNode rootNode];
  auto const component1 = [CKTreeNodeTest_RenderComponent_NoInitialState new];
  CKTreeNode *childNode1 = [CKTreeNode childPairForComponent:component1
                                                      parent:root1
                                              previousParent:nil
                                                   scopeRoot:scopeRoot
                                                stateUpdates:{}].node;

  // Simulate a component tree creation with a DIFFRENT child
  auto const root2 = [CKTreeNode rootNode];
  auto const component2 = [CKRenderComponent new];
  CKTreeNode *childNode2 = [CKTreeNode childPairForComponent:component2
                                                      parent:root2
                                              previousParent:root1
                                                   scopeRoot:[scopeRoot newRoot]
                                                stateUpdates:{}].node;

  XCTAssertTrue(verifyChildToParentConnection(root1, childNode1, component1));
  XCTAssertTrue(verifyChildToParentConnection(root2, childNode2, component2));
  XCTAssertNotEqual(childNode1.nodeIdentifier, childNode2.nodeIdentifier);
}


#pragma mark - Child key indexes

- (void)test_createKeyForOneHundredSameTypeSiblings_usesAtMostTwoHundredIdentifierComparisons
{
  auto const root = [CKTreeNode rootNode];
  const char *const componentTypeName = "CKTreeNodeTest_CountingComponent";
  const char *const interleavedTypeName = "CKTreeNodeTest_InterleavedComponent";

  [CKTreeNodeTest_CountingIdentifier resetEqualityComparisons];
  for (NSUInteger i = 0; i < 100; ++i) {
    auto const identifier = [CKTreeNodeTest_CountingIdentifier newWithValue:i hash:i];
    auto const key = [root createKeyForComponentTypeName:componentTypeName
                                              identifier:identifier
                                                    keys:{}
                                                    type:CKTreeNodeComponentKey::Type::parent];
    XCTAssertEqual(key.counter, (NSUInteger)0);
    [root setChild:[CKTreeNode rootNode] forComponentKey:key];

    auto const interleavedKey = [root createKeyForComponentTypeName:interleavedTypeName
                                                         identifier:@(i)
                                                               keys:{}
                                                               type:CKTreeNodeComponentKey::Type::parent];
    [root setChild:[CKTreeNode rootNode] forComponentKey:interleavedKey];
  }

  XCTAssertTrue([CKTreeNodeTest_CountingIdentifier equalityComparisons] <= 200,
                @"Expected at most 200 identifier comparisons, got %lu",
                (unsigned long)[CKTreeNodeTest_CountingIdentifier equalityComparisons]);
}

- (void)test_lookupForOneHundredSameTypeSiblings_usesAtMostTwoHundredIdentifierComparisons
{
  auto const root = [CKTreeNode rootNode];
  const char *const componentTypeName = "CKTreeNodeTest_CountingComponent";
  const char *const interleavedTypeName = "CKTreeNodeTest_InterleavedComponent";
  std::vector<CKTreeNodeComponentKey> keys;
  std::vector<CKTreeNode *> nodes;
  keys.reserve(100);
  nodes.reserve(100);

  for (NSUInteger i = 0; i < 100; ++i) {
    auto const identifier = [CKTreeNodeTest_CountingIdentifier newWithValue:i hash:i];
    auto const key = [root createKeyForComponentTypeName:componentTypeName
                                              identifier:identifier
                                                    keys:{}
                                                    type:CKTreeNodeComponentKey::Type::parent];
    auto const node = [CKTreeNode rootNode];
    [root setChild:node forComponentKey:key];
    keys.push_back(key);
    nodes.push_back(node);

    auto const interleavedKey = [root createKeyForComponentTypeName:interleavedTypeName
                                                         identifier:@(i)
                                                               keys:{}
                                                               type:CKTreeNodeComponentKey::Type::parent];
    [root setChild:[CKTreeNode rootNode] forComponentKey:interleavedKey];
  }

  [CKTreeNodeTest_CountingIdentifier resetEqualityComparisons];
  for (NSUInteger i = 0; i < 100; ++i) {
    auto lookupKey = keys[i];
    lookupKey.identifier = [CKTreeNodeTest_CountingIdentifier newWithValue:i hash:i];
    XCTAssertEqual([root childForComponentKey:lookupKey], nodes[i]);
  }

  XCTAssertTrue([CKTreeNodeTest_CountingIdentifier equalityComparisons] <= 200,
                @"Expected at most 200 identifier comparisons, got %lu",
                (unsigned long)[CKTreeNodeTest_CountingIdentifier equalityComparisons]);
}

- (void)test_keyIndex_preservesCountersOrderingAndLookupSemantics
{
  auto const root = [CKTreeNode rootNode];
  char componentTypeName[] = "CKTreeNodeTest_KeyedComponent";
  char equalButDifferentTypeName[] = "CKTreeNodeTest_KeyedComponent";
  XCTAssertNotEqual(componentTypeName, equalButDifferentTypeName);

  auto const nilParentNode = [CKTreeNode rootNode];
  auto const nilParentKey = [root createKeyForComponentTypeName:componentTypeName
                                                     identifier:nil
                                                           keys:{}
                                                           type:CKTreeNodeComponentKey::Type::parent];
  XCTAssertEqual(nilParentKey.counter, (NSUInteger)0);
  [root setChild:nilParentNode forComponentKey:nilParentKey];

  auto const nilOwnerNode = [CKTreeNode rootNode];
  auto const nilOwnerKey = [root createKeyForComponentTypeName:componentTypeName
                                                    identifier:nil
                                                          keys:{}
                                                          type:CKTreeNodeComponentKey::Type::owner];
  XCTAssertEqual(nilOwnerKey.counter, (NSUInteger)3);
  [root setChild:nilOwnerNode forComponentKey:nilOwnerKey];

  auto const firstIdentifier = [CKTreeNodeTest_CountingIdentifier newWithValue:1 hash:1];
  auto const firstParentNode = [CKTreeNode rootNode];
  auto const firstParentKey = [root createKeyForComponentTypeName:componentTypeName
                                                       identifier:firstIdentifier
                                                             keys:{}
                                                             type:CKTreeNodeComponentKey::Type::parent];
  XCTAssertEqual(firstParentKey.counter, (NSUInteger)0);
  [root setChild:firstParentNode forComponentKey:firstParentKey];

  auto const firstAuxiliaryKey = [CKTreeNodeTest_CountingIdentifier newWithValue:10 hash:10];
  auto const secondAuxiliaryKey = [CKTreeNodeTest_CountingIdentifier newWithValue:11 hash:11];
  auto const equalIdentifier = [CKTreeNodeTest_CountingIdentifier newWithValue:1 hash:1];
  auto const equalOwnerNode = [CKTreeNode rootNode];
  auto const equalOwnerKey = [root createKeyForComponentTypeName:componentTypeName
                                                      identifier:equalIdentifier
                                                            keys:{firstAuxiliaryKey, secondAuxiliaryKey}
                                                            type:CKTreeNodeComponentKey::Type::owner];
  XCTAssertEqual(equalOwnerKey.counter, (NSUInteger)3);
  [root setChild:equalOwnerNode forComponentKey:equalOwnerKey];

  auto const anotherEqualIdentifier = [CKTreeNodeTest_CountingIdentifier newWithValue:1 hash:1];
  auto const equalParentNode = [CKTreeNode rootNode];
  auto const equalParentKey = [root createKeyForComponentTypeName:componentTypeName
                                                       identifier:anotherEqualIdentifier
                                                             keys:{secondAuxiliaryKey, firstAuxiliaryKey}
                                                             type:CKTreeNodeComponentKey::Type::parent];
  XCTAssertEqual(equalParentKey.counter, (NSUInteger)4);
  [root setChild:equalParentNode forComponentKey:equalParentKey];

  auto const distinctIdentifier = [CKTreeNodeTest_CountingIdentifier newWithValue:2 hash:2];
  auto const distinctParentNode = [CKTreeNode rootNode];
  auto const distinctParentKey = [root createKeyForComponentTypeName:componentTypeName
                                                          identifier:distinctIdentifier
                                                                keys:{}
                                                                type:CKTreeNodeComponentKey::Type::parent];
  XCTAssertEqual(distinctParentKey.counter, (NSUInteger)0);
  [root setChild:distinctParentNode forComponentKey:distinctParentKey];

  auto const differentTypeNode = [CKTreeNode rootNode];
  auto const differentTypeKey = [root createKeyForComponentTypeName:equalButDifferentTypeName
                                                          identifier:firstIdentifier
                                                                keys:{}
                                                                type:CKTreeNodeComponentKey::Type::parent];
  XCTAssertEqual(differentTypeKey.counter, (NSUInteger)0);
  [root setChild:differentTypeNode forComponentKey:differentTypeKey];

  auto equalOwnerLookupKey = equalOwnerKey;
  equalOwnerLookupKey.identifier = [CKTreeNodeTest_CountingIdentifier newWithValue:1 hash:1];
  equalOwnerLookupKey.keys = {
    [CKTreeNodeTest_CountingIdentifier newWithValue:10 hash:10],
    [CKTreeNodeTest_CountingIdentifier newWithValue:11 hash:11],
  };
  XCTAssertEqual([root childForComponentKey:nilParentKey], nilParentNode);
  XCTAssertEqual([root childForComponentKey:nilOwnerKey], nilOwnerNode);
  XCTAssertEqual([root childForComponentKey:equalOwnerLookupKey], equalOwnerNode);
  XCTAssertEqual([root childForComponentKey:equalParentKey], equalParentNode);
  XCTAssertEqual([root childForComponentKey:differentTypeKey], differentTypeNode);

  auto const children = root.children;
  XCTAssertEqual(children.size(), (size_t)5);
  XCTAssertEqual(children[0], nilParentNode);
  XCTAssertEqual(children[1], firstParentNode);
  XCTAssertEqual(children[2], equalParentNode);
  XCTAssertEqual(children[3], distinctParentNode);
  XCTAssertEqual(children[4], differentTypeNode);
}

- (void)test_keyIndex_handlesHashCollisionsOrderedAuxiliaryKeysAndDuplicateFullKeys
{
  auto const root = [CKTreeNode rootNode];
  const char *const componentTypeName = "CKTreeNodeTest_CollidingComponent";
  std::vector<CKTreeNodeComponentKey> identifierKeys;
  std::vector<CKTreeNode *> identifierNodes;

  for (NSUInteger i = 0; i < 3; ++i) {
    auto const identifier = [CKTreeNodeTest_CountingIdentifier newWithValue:i hash:42];
    auto const key = [root createKeyForComponentTypeName:componentTypeName
                                              identifier:identifier
                                                    keys:{}
                                                    type:CKTreeNodeComponentKey::Type::parent];
    XCTAssertEqual(key.counter, (NSUInteger)0);
    auto const node = [CKTreeNode rootNode];
    [root setChild:node forComponentKey:key];
    identifierKeys.push_back(key);
    identifierNodes.push_back(node);
  }

  for (NSUInteger i = 0; i < identifierKeys.size(); ++i) {
    auto lookupKey = identifierKeys[i];
    lookupKey.identifier = [CKTreeNodeTest_CountingIdentifier newWithValue:i hash:42];
    XCTAssertEqual([root childForComponentKey:lookupKey], identifierNodes[i]);
  }

  auto const firstAuxiliaryKey = [CKTreeNodeTest_CountingIdentifier newWithValue:100 hash:7];
  auto const secondAuxiliaryKey = [CKTreeNodeTest_CountingIdentifier newWithValue:200 hash:7];
  CKTreeNodeComponentKey orderedKey{componentTypeName, 100, nil, {firstAuxiliaryKey, secondAuxiliaryKey}};
  CKTreeNodeComponentKey reversedKey{componentTypeName, 100, nil, {secondAuxiliaryKey, firstAuxiliaryKey}};
  auto const orderedNode = [CKTreeNode rootNode];
  auto const reversedNode = [CKTreeNode rootNode];
  auto const duplicateNode = [CKTreeNode rootNode];
  [root setChild:orderedNode forComponentKey:orderedKey];
  [root setChild:reversedNode forComponentKey:reversedKey];
  [root setChild:duplicateNode forComponentKey:orderedKey];

  auto orderedLookupKey = orderedKey;
  orderedLookupKey.keys = {
    [CKTreeNodeTest_CountingIdentifier newWithValue:100 hash:7],
    [CKTreeNodeTest_CountingIdentifier newWithValue:200 hash:7],
  };
  auto reversedLookupKey = reversedKey;
  reversedLookupKey.keys = {
    [CKTreeNodeTest_CountingIdentifier newWithValue:200 hash:7],
    [CKTreeNodeTest_CountingIdentifier newWithValue:100 hash:7],
  };
  XCTAssertEqual([root childForComponentKey:orderedLookupKey], orderedNode);
  XCTAssertEqual([root childForComponentKey:reversedLookupKey], reversedNode);
}

- (void)test_keyIndex_isRebuiltAfterReusingPreviousNode
{
  auto const scopeRoot = CKComponentScopeRootWithDefaultPredicates(nil, nil);
  auto const previousNode = [CKTreeNode rootNode];
  const char *const componentTypeName = "CKTreeNodeTest_ReusedComponent";
  auto const firstChild = [CKTreeNode rootNode];
  auto const secondChild = [CKTreeNode rootNode];
  auto const firstKey = [previousNode createKeyForComponentTypeName:componentTypeName
                                                         identifier:@1
                                                               keys:{}
                                                               type:CKTreeNodeComponentKey::Type::parent];
  [previousNode setChild:firstChild forComponentKey:firstKey];
  auto const secondKey = [previousNode createKeyForComponentTypeName:componentTypeName
                                                          identifier:@2
                                                                keys:{}
                                                                type:CKTreeNodeComponentKey::Type::parent];
  [previousNode setChild:secondChild forComponentKey:secondKey];
  XCTAssertEqual([previousNode childForComponentKey:firstKey], firstChild);

  auto const reusedNode = [CKTreeNode rootNode];
  const char *const staleTypeName = "CKTreeNodeTest_StaleComponent";
  auto const staleKey = [reusedNode createKeyForComponentTypeName:staleTypeName
                                                       identifier:nil
                                                             keys:{}
                                                             type:CKTreeNodeComponentKey::Type::parent];
  [reusedNode setChild:[CKTreeNode rootNode] forComponentKey:staleKey];
  XCTAssertNotNil([reusedNode childForComponentKey:staleKey]);

  [reusedNode reusePreviousNode:previousNode inScopeRoot:scopeRoot];

  XCTAssertNil([reusedNode childForComponentKey:staleKey]);
  XCTAssertEqual([reusedNode childForComponentKey:firstKey], firstChild);
  XCTAssertEqual([reusedNode childForComponentKey:secondKey], secondChild);
  auto const nextFirstKey = [reusedNode createKeyForComponentTypeName:componentTypeName
                                                            identifier:@1
                                                                  keys:{}
                                                                  type:CKTreeNodeComponentKey::Type::parent];
  XCTAssertEqual(nextFirstKey.counter, (NSUInteger)2);
  auto const children = reusedNode.children;
  XCTAssertEqual(children.size(), (size_t)2);
  XCTAssertEqual(children[0], firstChild);
  XCTAssertEqual(children[1], secondChild);
}

#pragma mark - State

- (void)test_stateUpdate_onCKTreeNode
{
  // The 'resolve' method in CKComponentScopeHandle requires a CKThreadLocalComponentScope.
  // We should get rid of this assert once we move to the render method only.
  CKThreadLocalComponentScope threadScope(CKComponentScopeRootWithDefaultPredicates(nil, nil), {});

  // Simulate first component tree creation
  auto const root1 = [CKTreeNode rootNode];
  auto const component1 = [CKTreeNodeTest_RenderComponent_WithState new];
  CKTreeNode *childNode = [CKTreeNode childPairForComponent:component1
                                                     parent:root1
                                             previousParent:nil
                                                  scopeRoot:threadScope.newScopeRoot
                                               stateUpdates:{}].node;

  // Verify that the initial state is correct.
  XCTAssertTrue([childNode.state isEqualToNumber:[[component1 class] initialState]]);

  // Simulate a component tree creation due to a state update
  auto const root2 = [CKTreeNode rootNode];
  auto const component2 = [CKTreeNodeTest_RenderComponent_WithState new];

  // Simulate a state update
  auto const newState = @2;
  auto const scopeHandle = childNode.scopeHandle;
  CKComponentStateUpdateMap stateUpdates;
  stateUpdates[scopeHandle].push_back(^(id){
    return newState;
  });
  CKTreeNode *childNode2 = [CKTreeNode childPairForComponent:component2
                                                      parent:root2
                                              previousParent:root1
                                                   scopeRoot:[threadScope.newScopeRoot newRoot]
                                                stateUpdates:stateUpdates].node;

  XCTAssertTrue([childNode2.state isEqualToNumber:newState]);
}

- (void)test_nonNil_initialState_onCKTreeNode_withCKComponentSubclass
{
  __block CKComponent *c;
  buildComponent(^CKComponent*{
    c = [CKTreeNodeTest_Component_WithState new];
    // Using flexbox here to add a render component to the hierarchy, which forces buildComponentTree:
    return CK::FlexboxComponentBuilder()
    .child(c)
    .child([CKTreeNodeTest_RenderComponent_WithNilState new])
    .build();
  });
  [self _test_nonNil_initialState_withComponent:c];
}

- (void)test_emptyInitialState_onCKTreeNode_withCKComponentSubclass
{
  auto const c = buildComponent(^{ return [CKComponent new]; });
  [self _test_emptyInitialState_withComponent:c];
}

- (void)test_nonNil_initialState_onCKRenderTreeNode_withCKRenderComponent
{
  auto const c = buildComponent(^{ return [CKTreeNodeTest_RenderComponent_WithState new]; });
  [self _test_nonNil_initialState_withComponent:c];
}

- (void)test_emptyInitialState_onCKRenderTreeNode_withCKRenderComponent
{
  auto const c = buildComponent(^{ return [CKTreeNodeTest_RenderComponent_NoInitialState new]; });
  [self _test_emptyInitialState_withComponent:c];
}

- (void)test_initialStateFromProps_onCKRenderTreeNode_withCKRenderComponent
{
  id prop = @1;
  auto const c = buildComponent(^{ return [CKTreeNodeTest_RenderComponent_WithStateFromProps newWithProp:prop]; });
  [self _test_initialState_withComponent:c initialState:prop];
}

- (void)test_nilInitialState_onCKRenderTreeNode_withCKRenderComponent
{
  // Make sure CKRenderComponent supports nil initial state from prop.
  id prop = nil;
  auto const c = buildComponent(^{ return [CKTreeNodeTest_RenderComponent_WithStateFromProps newWithProp:prop]; });
  [self _test_initialState_withComponent:c initialState:nil];

  // Make sure CKRenderComponent supports nil initial.
  auto const c2 = buildComponent(^{ return [CKTreeNodeTest_RenderComponent_WithNilState new]; });
  [self _test_initialState_withComponent:c2 initialState:nil];
}

- (void)test_componentIdentifierOnCKTreeNodeWithChildren_withReorder {
  // Simulate first component tree creation
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *c1;
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *c2;
  auto const results = CKBuildComponent(CKComponentScopeRootWithDefaultPredicates(nil, nil), {}, ^CKComponent *{
    c1 = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:@1];
    c2 = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:@2];
    return CK::FlexboxComponentBuilder()
    .alignItems(CKFlexboxAlignItemsStretch)
    .child(c1)
    .child(c2)
    .build();
  });

  // Simulate a props update which *reorders* the children.
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *c1SecondGen;
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *c2SecondGen;
  auto const results2 = CKBuildComponent(results.scopeRoot, {}, ^CKComponent *{
    c1SecondGen = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:@1];
    c2SecondGen = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:@2];
    return CK::FlexboxComponentBuilder()
    .alignItems(CKFlexboxAlignItemsStretch)
    .child(c2SecondGen)
    .child(c1SecondGen)
    .build();
  });

  // Make sure each component retreive its correct state even after reorder.
  XCTAssertEqual(c1.treeNode.scopeHandle.state, c1SecondGen.treeNode.scopeHandle.state);
  XCTAssertEqual(c2.treeNode.scopeHandle.state, c2SecondGen.treeNode.scopeHandle.state);
}

- (void)test_componentIdentifierOnCKTreeNodeWithChildren_withRemovingComponents {
  // Simulate first component tree creation
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *c1;
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *c2;
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *c3;
  auto const results = CKBuildComponent(CKComponentScopeRootWithDefaultPredicates(nil, nil), {}, ^CKComponent *{
    c1 = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:@1];
    c2 = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:@2];
    c3 = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:@3];
    return CK::FlexboxComponentBuilder()
    .alignItems(CKFlexboxAlignItemsStretch)
    .child(c1)
    .child(c2)
    .child(c3)
    .build();
  });

  // Simulate a props update which *removes* c2 from the hierarchy.
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *c1SecondGen;
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *c3SecondGen;
  auto const results2 = CKBuildComponent(results.scopeRoot, {}, ^CKComponent *{
    c1SecondGen = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:@1];
    c3SecondGen = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:@3];
    return CK::FlexboxComponentBuilder()
    .alignItems(CKFlexboxAlignItemsStretch)
    .child(c1SecondGen)
    .child(c3SecondGen)
    .build();
  });

  // Make sure each component retreive its correct state even after reorder.
  XCTAssertEqual(c1.treeNode.scopeHandle.state, c1SecondGen.treeNode.scopeHandle.state);
  XCTAssertEqual(c3.treeNode.scopeHandle.state, c3SecondGen.treeNode.scopeHandle.state);
}


- (void)test_componentIdentifierIndex_preservesIdentityStateAndOrderAcrossReorderInsertionAndRemoval
{
  auto const firstIdentifier = [CKTreeNodeTest_CountingIdentifier newWithValue:1 hash:1];
  auto const removedIdentifier = [CKTreeNodeTest_CountingIdentifier newWithValue:2 hash:2];
  auto const thirdIdentifier = [CKTreeNodeTest_CountingIdentifier newWithValue:3 hash:3];
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *firstComponent;
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *removedComponent;
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *thirdComponent;
  auto const firstResults = CKBuildComponent(CKComponentScopeRootWithDefaultPredicates(nil, nil), {}, ^CKComponent *{
    firstComponent = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:firstIdentifier];
    removedComponent = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:removedIdentifier];
    thirdComponent = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:thirdIdentifier];
    return CK::FlexboxComponentBuilder()
    .alignItems(CKFlexboxAlignItemsStretch)
    .child(firstComponent)
    .child(removedComponent)
    .child(thirdComponent)
    .build();
  });

  auto const equalFirstIdentifier = [CKTreeNodeTest_CountingIdentifier newWithValue:1 hash:1];
  auto const insertedIdentifier = [CKTreeNodeTest_CountingIdentifier newWithValue:4 hash:4];
  auto const equalThirdIdentifier = [CKTreeNodeTest_CountingIdentifier newWithValue:3 hash:3];
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *firstComponentSecondGeneration;
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *insertedComponent;
  __block CKTreeNodeTest_RenderComponent_WithIdentifier *thirdComponentSecondGeneration;
  auto const secondResults = CKBuildComponent(firstResults.scopeRoot, {}, ^CKComponent *{
    thirdComponentSecondGeneration = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:equalThirdIdentifier];
    insertedComponent = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:insertedIdentifier];
    firstComponentSecondGeneration = [CKTreeNodeTest_RenderComponent_WithIdentifier newWithIdentifier:equalFirstIdentifier];
    return CK::FlexboxComponentBuilder()
    .alignItems(CKFlexboxAlignItemsStretch)
    .child(thirdComponentSecondGeneration)
    .child(insertedComponent)
    .child(firstComponentSecondGeneration)
    .build();
  });

  XCTAssertEqual(firstComponent.treeNode.nodeIdentifier,
                 firstComponentSecondGeneration.treeNode.nodeIdentifier);
  XCTAssertEqual(thirdComponent.treeNode.nodeIdentifier,
                 thirdComponentSecondGeneration.treeNode.nodeIdentifier);
  XCTAssertNotEqual(removedComponent.treeNode.nodeIdentifier, insertedComponent.treeNode.nodeIdentifier);
  XCTAssertEqual(firstComponentSecondGeneration.treeNode.scopeHandle.state, firstIdentifier);
  XCTAssertEqual(thirdComponentSecondGeneration.treeNode.scopeHandle.state, thirdIdentifier);
  XCTAssertEqual(insertedComponent.treeNode.scopeHandle.state, insertedIdentifier);
  XCTAssertNotEqual(firstComponentSecondGeneration.treeNode.scopeHandle.state, equalFirstIdentifier);
  XCTAssertNotEqual(thirdComponentSecondGeneration.treeNode.scopeHandle.state, equalThirdIdentifier);

  auto const previousParent = firstResults.scopeRoot.rootNode.parentForNodeIdentifier(firstComponent.treeNode.nodeIdentifier);
  auto const parent = secondResults.scopeRoot.rootNode.parentForNodeIdentifier(firstComponentSecondGeneration.treeNode.nodeIdentifier);
  XCTAssertEqual(previousParent.children.size(), (size_t)3);
  XCTAssertEqual(previousParent.children[0], firstComponent.treeNode);
  XCTAssertEqual(previousParent.children[1], removedComponent.treeNode);
  XCTAssertEqual(previousParent.children[2], thirdComponent.treeNode);
  XCTAssertEqual(parent.children.size(), (size_t)3);
  XCTAssertEqual(parent.children[0], thirdComponentSecondGeneration.treeNode);
  XCTAssertEqual(parent.children[1], insertedComponent.treeNode);
  XCTAssertEqual(parent.children[2], firstComponentSecondGeneration.treeNode);
  XCTAssertNil([parent childForComponentKey:removedComponent.treeNode.componentKey]);
  XCTAssertEqual([parent childForComponentKey:insertedComponent.treeNode.componentKey], insertedComponent.treeNode);
}

#pragma mark - Helpers

- (void)_test_emptyInitialState_withComponent:(CKComponent *)c
{
  XCTAssertNil(c.treeNode.scopeHandle.state);
}

- (void)_test_nonNil_initialState_withComponent:(CKComponent *)c
{
  XCTAssertEqual([[c class] initialState], c.treeNode.scopeHandle.state);
  XCTAssertNotNil(c.treeNode.scopeHandle);
}

- (void)_test_initialState_withComponent:(CKComponent *)c initialState:(id)initialState
{
  XCTAssertEqual(initialState, c.treeNode.scopeHandle.state);
  XCTAssertNotNil(c.treeNode.scopeHandle);
}

@end

@interface CKRenderTreeNodeTests : CKComponentTestCase
@end

@implementation CKRenderTreeNodeTests

#pragma mark - CKTreeNodeWithChild

- (void)test_childForComponentKey_onCKTreeNodeWithChild {
  // Simulate first component tree creation
  auto const scopeRoot = CKComponentScopeRootWithDefaultPredicates(nil, nil);
  CKTreeNode *root1 = [CKTreeNode rootNode];
  auto const component1 = [CKTreeNodeTest_RenderComponent_NoInitialState new];
  CKTreeNode *childNode1 = [CKTreeNode childPairForComponent:component1
                                                      parent:root1
                                              previousParent:nil
                                                   scopeRoot:scopeRoot
                                                stateUpdates:{}].node;

  // Simulate a component tree creation due to a state update
  CKTreeNode *root2 = [CKTreeNode rootNode];
  auto const component2 = [CKTreeNodeTest_RenderComponent_NoInitialState new];
  CKTreeNode *childNode2 = [CKTreeNode childPairForComponent:component2
                                                      parent:root2
                                                      previousParent:root1
                                                      scopeRoot:[scopeRoot newRoot]
                                                      stateUpdates:{}].node;

  XCTAssertTrue(verifyChildToParentConnection(root1, childNode1, component1));
  XCTAssertTrue(verifyChildToParentConnection(root2, childNode2, component2));
}

- (void)test_nodeIdentifier_onCKTreeNodeWithChild_betweenGenerations {
  // Simulate first component tree creation
  auto const scopeRoot = CKComponentScopeRootWithDefaultPredicates(nil, nil);
  CKTreeNode *root1 = [CKTreeNode rootNode];
  auto const component1 = [CKTreeNodeTest_RenderComponent_NoInitialState new];
  CKTreeNode *childNode1 = [CKTreeNode childPairForComponent:component1
                                                      parent:root1
                                              previousParent:nil
                                                   scopeRoot:scopeRoot
                                                stateUpdates:{}].node;

  // Simulate a component tree creation due to a state update
  CKTreeNode *root2 = [CKTreeNode rootNode];
  auto const component2 = [CKTreeNodeTest_RenderComponent_NoInitialState new];
  CKTreeNode *childNode2 = [CKTreeNode childPairForComponent:component2
                                                      parent:root2
                                              previousParent:root1
                                                   scopeRoot:[scopeRoot newRoot]
                                                stateUpdates:{}].node;

  XCTAssertEqual(childNode1.nodeIdentifier, childNode2.nodeIdentifier);
}

- (void)test_childForComponentKey_onCKTreeNodeWithChild_withSameChildOverGenerations
{
  // Simulate first component tree creation
  auto const scopeRoot = CKComponentScopeRootWithDefaultPredicates(nil, nil);
  CKTreeNode *root1 = [CKTreeNode rootNode];
  auto const component1 = [CKTreeNodeTest_RenderComponent_NoInitialState new];
  CKTreeNode *childNode1 = [CKTreeNode childPairForComponent:component1
                                                      parent:root1
                                              previousParent:nil
                                                   scopeRoot:scopeRoot
                                                stateUpdates:{}].node;


  // Simulate a component tree creation due to a state update
  CKTreeNode *root2 = [CKTreeNode rootNode];
  auto const component2 = [CKTreeNodeTest_RenderComponent_NoInitialState new];
  CKTreeNode *childNode2 = [CKTreeNode childPairForComponent:component2
                                                      parent:root2
                                              previousParent:root1
                                                   scopeRoot:[scopeRoot newRoot]
                                                stateUpdates:{}].node;

  XCTAssertTrue(verifyChildToParentConnection(root1, childNode1, component1));
  XCTAssertTrue(verifyChildToParentConnection(root2, childNode2, component2));
  XCTAssertEqual(childNode1.nodeIdentifier, childNode2.nodeIdentifier);
}

- (void)test_childForComponentKey_onCKTreeNodeWithChild_withDifferentChildOverGenerations
{
  // Simulate first component tree creation
  auto const scopeRoot = CKComponentScopeRootWithDefaultPredicates(nil, nil);
  CKTreeNode *root1 = [CKTreeNode rootNode];
  auto const component1 = [CKTreeNodeTest_RenderComponent_NoInitialState new];
  CKTreeNode *childNode1 = [CKTreeNode childPairForComponent:component1
                                                      parent:root1
                                              previousParent:nil
                                                   scopeRoot:scopeRoot
                                                stateUpdates:{}].node;



  // Simulate a component tree creation with a DIFFRENT child
  CKTreeNode *root2 = [CKTreeNode rootNode];
  auto const component2 = [CKRenderComponent new];
  CKTreeNode *childNode2 = [CKTreeNode childPairForComponent:component2
                                                      parent:root2
                                              previousParent:root1
                                                   scopeRoot:[scopeRoot newRoot]
                                                stateUpdates:{}].node;

  XCTAssertTrue(verifyChildToParentConnection(root1, childNode1, component1));
  XCTAssertTrue(verifyChildToParentConnection(root2, childNode2, component2));
  XCTAssertNotEqual(childNode1.nodeIdentifier, childNode2.nodeIdentifier);
}

@end

#pragma mark - Helper Classes

@implementation CKTreeNodeTest_Component_WithState
+ (id)initialState
{
  return @1;
}

+ (instancetype)new
{
  CKComponentScope scope(self);
  return [super new];
}
@end

@implementation CKTreeNodeTest_RenderComponent_WithState
+ (id)initialState
{
  return @1;
}
- (CKComponent *)render:(id)state
{
  return [CKComponent new];
}
@end

@implementation CKTreeNodeTest_RenderComponent_WithStateFromProps
{
  id _prop;
}

+ (instancetype)newWithProp:(id)prop
{
  auto const c = [super new];
  if (c) {
    c->_prop = prop;
  }
  return c;
}

- (id)initialState
{
  return _prop;
}

- (CKComponent *)render:(id)state
{
  return [CKComponent new];
}
@end

@implementation CKTreeNodeTest_RenderComponent_WithNilState
+ (id)initialState
{
  return nil;
}

- (CKComponent *)render:(id)state
{
  return [CKComponent new];
}
@end

@implementation CKTreeNodeTest_Component_WithScope
+ (instancetype)new
{
  CKComponentScope scope(self);
  return [super new];
}
@end

@implementation CKTreeNodeTest_RenderComponent_WithChild
+ (instancetype)newWithComponent:(CKComponent *)component
{
  auto const c = [super new];
  if (c) {
    c->_childComponent = component;
  }
  return c;
}

+ (id)initialState
{
  return nil;
}

- (CKComponent *)render:(id)state
{
  return _childComponent;
}
@end

static NSUInteger CKTreeNodeTestIdentifierEqualityComparisons = 0;

@implementation CKTreeNodeTest_CountingIdentifier
{
  NSUInteger _value;
  NSUInteger _hashValue;
}

+ (instancetype)newWithValue:(NSUInteger)value hash:(NSUInteger)hash
{
  auto const identifier = [super new];
  if (identifier) {
    identifier->_value = value;
    identifier->_hashValue = hash;
  }
  return identifier;
}

+ (void)resetEqualityComparisons
{
  CKTreeNodeTestIdentifierEqualityComparisons = 0;
}

+ (NSUInteger)equalityComparisons
{
  return CKTreeNodeTestIdentifierEqualityComparisons;
}

- (BOOL)isEqual:(id)object
{
  ++CKTreeNodeTestIdentifierEqualityComparisons;
  return [object isKindOfClass:[CKTreeNodeTest_CountingIdentifier class]]
    && _value == ((CKTreeNodeTest_CountingIdentifier *)object)->_value;
}

- (NSUInteger)hash
{
  return _hashValue;
}

@end

@implementation CKTreeNodeTest_RenderComponent_WithIdentifier
{
  id<NSObject> _identifier;
}

+ (instancetype)newWithIdentifier:(id<NSObject>)identifier
{
  auto const c = [super new];
  if (c) {
    c->_identifier = identifier;
  }
  return c;
}

- (id<NSObject>)componentIdentifier
{
  return _identifier;
}

- (CKComponent *)render:(id)state
{
  return [CKComponent new];
}

- (id)initialState
{
  return _identifier;
}

@end

@implementation CKTreeNodeTest_RenderComponent_NoInitialState
- (CKComponent *)render:(id)state
{
  return [CKComponent new];
}
@end
