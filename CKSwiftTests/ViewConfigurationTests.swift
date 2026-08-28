/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

import CKSwift
import UIKit
import XCTest

@objc(CKSwiftAttributeTestLayer)
private final class AttributeTestLayer: CALayer {
  private(set) var borderColorSetCount = 0
  private(set) var cornerRadiusSetCount = 0

  override var borderColor: CGColor? {
    didSet {
      borderColorSetCount += 1
    }
  }

  override var cornerRadius: CGFloat {
    didSet {
      cornerRadiusSetCount += 1
    }
  }
}

@objc(CKSwiftAttributeTestView)
private final class AttributeTestView: UIView {
  override class var layerClass: AnyClass {
    AttributeTestLayer.self
  }

  override var backgroundColor: UIColor? {
    didSet {
      backgroundColorSetCount += 1
    }
  }

  override var alpha: CGFloat {
    didSet {
      alphaSetCount += 1
    }
  }

  @objc dynamic var objectValue: NSString? {
    didSet {
      objectValueSetCount += 1
    }
  }

  @objc dynamic var scalarValue: CGFloat = 0 {
    didSet {
      scalarValueSetCount += 1
    }
  }

  @objc dynamic var enumValue: UIView.ContentMode = .scaleToFill {
    didSet {
      enumValueSetCount += 1
    }
  }

  @objc dynamic var rectangleValue: CGRect = .zero {
    didSet {
      rectangleValueSetCount += 1
    }
  }

  private(set) var backgroundColorSetCount = 0
  private(set) var alphaSetCount = 0
  private(set) var objectValueSetCount = 0
  private(set) var scalarValueSetCount = 0
  private(set) var enumValueSetCount = 0
  private(set) var rectangleValueSetCount = 0

  var testLayer: AttributeTestLayer {
    layer as! AttributeTestLayer
  }
}

private final class MountedComponentModel: NSObject {
  let makeComponent: () -> Component

  init(makeComponent: @escaping () -> Component) {
    self.makeComponent = makeComponent
  }
}

private final class ComponentMountHarness {
  let hostingView: ComponentHostingView<MountedComponentModel, NSObject>

  init() {
    hostingView = ComponentHostingView<MountedComponentModel, NSObject>(
      componentProvider: { model, _ in model?.makeComponent() },
      sizeRangeProviderBlock: { size in
        SizeRange(minSize: size, maxSize: size)
      }
    )
    hostingView.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
  }

  @discardableResult
  func mount(_ makeComponent: @escaping () -> Component) -> AttributeTestView {
    hostingView.updateModel(MountedComponentModel(makeComponent: makeComponent), mode: .synchronous)
    hostingView.layoutIfNeeded()

    guard let container = hostingView.subviews.first,
          let mountedView = container.subviews.first as? AttributeTestView else {
      preconditionFailure("Expected an AttributeTestView to be mounted")
    }
    return mountedView
  }
}

private final class GestureInvocationRecorder: NSObject {
  var invocationCount = 0
  weak var lastRecognizer: UIGestureRecognizer?
}

private struct GestureCompatibleView: CKSwift.View, ViewConfigurationRepresentable, Actionable {
  typealias Body = Never

  let color: UIColor
  let recorder: GestureInvocationRecorder

  var viewConfiguration: ViewConfiguration {
    ViewConfiguration(viewClass: AttributeTestView.self) {
      (\AttributeTestView.backgroundColor, color)
      onTap { (_: GestureCompatibleView, recognizer: UIGestureRecognizer) in
        self.recorder.invocationCount += 1
        self.recorder.lastRecognizer = recognizer
      }
    }
  }
}

final class ViewConfigurationTests: XCTestCase {
  func testChangedValuesAreAppliedToReusedViewAndLayer() {
    let harness = ComponentMountHarness()
    let firstObject = NSString(string: "first")
    let secondObject = NSString(string: "second")
    let firstRect = CGRect(x: 1, y: 2, width: 3, height: 4)
    let secondRect = CGRect(x: 5, y: 6, width: 7, height: 8)

    let firstView = harness.mount {
      Component(view: self.directConfiguration(
        color: .red,
        alpha: 0.25,
        contentMode: .scaleAspectFit,
        objectValue: firstObject,
        scalarValue: 10,
        enumValue: .center,
        rectangleValue: firstRect,
        cornerRadius: 4
      ))
    }
    let firstLayer = firstView.layer
    let initialObjectSetCount = firstView.objectValueSetCount
    let initialScalarSetCount = firstView.scalarValueSetCount
    let initialEnumSetCount = firstView.enumValueSetCount
    let initialRectangleSetCount = firstView.rectangleValueSetCount
    let initialCornerRadiusSetCount = firstView.testLayer.cornerRadiusSetCount

    let secondView = harness.mount {
      Component(view: self.directConfiguration(
        color: .blue,
        alpha: 0.75,
        contentMode: .scaleAspectFill,
        objectValue: secondObject,
        scalarValue: 20,
        enumValue: .bottom,
        rectangleValue: secondRect,
        cornerRadius: 12
      ))
    }

    XCTAssertTrue(firstView === secondView)
    XCTAssertTrue(firstLayer === secondView.layer)
    XCTAssertEqual(secondView.backgroundColor, .blue)
    XCTAssertEqual(secondView.alpha, 0.75)
    XCTAssertEqual(secondView.contentMode, .scaleAspectFill)
    XCTAssertEqual(secondView.objectValue, secondObject)
    XCTAssertEqual(secondView.scalarValue, 20)
    XCTAssertEqual(secondView.enumValue, .bottom)
    XCTAssertEqual(secondView.rectangleValue, secondRect)
    XCTAssertEqual(secondView.layer.cornerRadius, 12)
    XCTAssertEqual(secondView.objectValueSetCount, initialObjectSetCount + 1)
    XCTAssertEqual(secondView.scalarValueSetCount, initialScalarSetCount + 1)
    XCTAssertEqual(secondView.enumValueSetCount, initialEnumSetCount + 1)
    XCTAssertEqual(secondView.rectangleValueSetCount, initialRectangleSetCount + 1)
    XCTAssertEqual(secondView.testLayer.cornerRadiusSetCount, initialCornerRadiusSetCount + 1)
  }

  func testEqualValuesAreNotReapplied() {
    let harness = ComponentMountHarness()
    let firstObject = NSMutableString(string: "equal")
    let equalButDistinctObject = NSMutableString(string: "equal")
    let rect = CGRect(x: 1, y: 2, width: 3, height: 4)
    XCTAssertFalse(firstObject === equalButDistinctObject)

    let firstView = harness.mount {
      Component(view: self.valueCategoryConfiguration(
        objectValue: firstObject,
        scalarValue: 0.625,
        enumValue: .right,
        rectangleValue: rect,
        cornerRadius: 9
      ))
    }
    let objectSetCount = firstView.objectValueSetCount
    let scalarSetCount = firstView.scalarValueSetCount
    let enumSetCount = firstView.enumValueSetCount
    let rectangleSetCount = firstView.rectangleValueSetCount
    let cornerRadiusSetCount = firstView.testLayer.cornerRadiusSetCount

    let secondView = harness.mount {
      Component(view: self.valueCategoryConfiguration(
        objectValue: equalButDistinctObject,
        scalarValue: 0.625,
        enumValue: .right,
        rectangleValue: rect,
        cornerRadius: 9
      ))
    }

    XCTAssertTrue(firstView === secondView)
    XCTAssertEqual(secondView.objectValueSetCount, objectSetCount)
    XCTAssertEqual(secondView.scalarValueSetCount, scalarSetCount)
    XCTAssertEqual(secondView.enumValueSetCount, enumSetCount)
    XCTAssertEqual(secondView.rectangleValueSetCount, rectangleSetCount)
    XCTAssertEqual(secondView.testLayer.cornerRadiusSetCount, cornerRadiusSetCount)
  }

  func testOptionalViewAndLayerValuesTransitionThroughNil() {
    let harness = ComponentMountHarness()
    let firstObject = NSString(string: "first")
    let secondObject = NSString(string: "second")
    let red = UIColor.red.cgColor
    let blue = UIColor.blue.cgColor

    let firstView = harness.mount {
      Component(view: self.optionalConfiguration(objectValue: firstObject, borderColor: red))
    }
    let firstSetCount = firstView.objectValueSetCount
    let firstBorderColorSetCount = firstView.testLayer.borderColorSetCount
    XCTAssertEqual(firstView.objectValue, firstObject)
    XCTAssertEqual(firstView.layer.borderColor, red)

    let nilView = harness.mount {
      Component(view: self.optionalConfiguration(objectValue: nil, borderColor: nil))
    }
    XCTAssertTrue(firstView === nilView)
    XCTAssertNil(nilView.objectValue)
    XCTAssertNil(nilView.layer.borderColor)
    XCTAssertEqual(nilView.objectValueSetCount, firstSetCount + 1)
    XCTAssertEqual(nilView.testLayer.borderColorSetCount, firstBorderColorSetCount + 1)

    let equalNilView = harness.mount {
      Component(view: self.optionalConfiguration(objectValue: nil, borderColor: nil))
    }
    XCTAssertTrue(firstView === equalNilView)
    XCTAssertNil(equalNilView.objectValue)
    XCTAssertNil(equalNilView.layer.borderColor)
    XCTAssertEqual(equalNilView.objectValueSetCount, firstSetCount + 1)
    XCTAssertEqual(equalNilView.testLayer.borderColorSetCount, firstBorderColorSetCount + 1)

    let finalView = harness.mount {
      Component(view: self.optionalConfiguration(objectValue: secondObject, borderColor: blue))
    }
    XCTAssertTrue(firstView === finalView)
    XCTAssertEqual(finalView.objectValue, secondObject)
    XCTAssertEqual(finalView.layer.borderColor, blue)
    XCTAssertEqual(finalView.objectValueSetCount, firstSetCount + 2)
    XCTAssertEqual(finalView.testLayer.borderColorSetCount, firstBorderColorSetCount + 2)
  }

  func testResultBuilderAndFluentModifiersReconcileConsistently() {
    let harness = ComponentMountHarness()

    let builderView = harness.mount {
      Component(view: ViewConfiguration(viewClass: AttributeTestView.self) {
        (\AttributeTestView.backgroundColor, UIColor.red as UIColor?)
        (\AttributeTestView.alpha, CGFloat(0.2))
        (\CALayer.cornerRadius, CGFloat(3))
      })
    }

    let fluentView = harness.mount {
      ComponentView<AttributeTestView>()
        .backgroundColor(.green)
        .alpha(0.8)
        .cornerRadius(11)
        .inflateComponent(with: nil)
    }

    XCTAssertTrue(builderView === fluentView)
    XCTAssertEqual(fluentView.backgroundColor, .green)
    XCTAssertEqual(fluentView.alpha, 0.8, accuracy: 0.000_001)
    XCTAssertEqual(fluentView.layer.cornerRadius, 11)
    let backgroundColorSetCount = fluentView.backgroundColorSetCount
    let alphaSetCount = fluentView.alphaSetCount
    let cornerRadiusSetCount = fluentView.testLayer.cornerRadiusSetCount

    let equalBuilderView = harness.mount {
      Component(view: ViewConfiguration(viewClass: AttributeTestView.self) {
        (\AttributeTestView.backgroundColor, UIColor.green as UIColor?)
        (\AttributeTestView.alpha, CGFloat(0.8))
        (\CALayer.cornerRadius, CGFloat(11))
      })
    }
    XCTAssertTrue(builderView === equalBuilderView)
    XCTAssertEqual(equalBuilderView.backgroundColorSetCount, backgroundColorSetCount)
    XCTAssertEqual(equalBuilderView.alphaSetCount, alphaSetCount)
    XCTAssertEqual(equalBuilderView.testLayer.cornerRadiusSetCount, cornerRadiusSetCount)

    let equalFluentView = harness.mount {
      ComponentView<AttributeTestView>()
        .backgroundColor(.green)
        .alpha(0.8)
        .cornerRadius(11)
        .inflateComponent(with: nil)
    }
    XCTAssertTrue(builderView === equalFluentView)
    XCTAssertEqual(equalFluentView.backgroundColorSetCount, backgroundColorSetCount)
    XCTAssertEqual(equalFluentView.alphaSetCount, alphaSetCount)
    XCTAssertEqual(equalFluentView.testLayer.cornerRadiusSetCount, cornerRadiusSetCount)
  }

  func testFluentOptionalModifierReconcilesNonNilAndNil() {
    let harness = ComponentMountHarness()

    let firstView = harness.mount {
      ComponentView<AttributeTestView>()
        .backgroundColor(.purple)
        .inflateComponent(with: nil)
    }
    let nilView = harness.mount {
      ComponentView<AttributeTestView>()
        .backgroundColor(nil)
        .inflateComponent(with: nil)
    }
    XCTAssertTrue(firstView === nilView)
    XCTAssertNil(nilView.backgroundColor)

    let finalView = harness.mount {
      ComponentView<AttributeTestView>()
        .backgroundColor(.orange)
        .inflateComponent(with: nil)
    }

    XCTAssertTrue(firstView === finalView)
    XCTAssertEqual(finalView.backgroundColor, .orange)
  }

  func testGestureAttributeStillInstallsAndInvokesAcrossValueChanges() {
    let harness = ComponentMountHarness()
    let recorder = GestureInvocationRecorder()

    let firstView = harness.mount {
      GestureCompatibleView(color: .red, recorder: recorder).inflateComponent(with: nil)
    }
    let firstRecognizer = tryUnwrapTapRecognizer(from: firstView)
    invokeComponentKitGesture(firstRecognizer)
    XCTAssertEqual(recorder.invocationCount, 1)
    XCTAssertTrue(recorder.lastRecognizer === firstRecognizer)

    let secondView = harness.mount {
      GestureCompatibleView(color: .blue, recorder: recorder).inflateComponent(with: nil)
    }
    let secondRecognizer = tryUnwrapTapRecognizer(from: secondView)
    invokeComponentKitGesture(secondRecognizer)

    XCTAssertTrue(firstView === secondView)
    XCTAssertEqual(secondView.backgroundColor, .blue)
    XCTAssertEqual(secondView.gestureRecognizers?.count, 1)
    XCTAssertEqual(recorder.invocationCount, 2)
    XCTAssertTrue(recorder.lastRecognizer === secondRecognizer)
  }

  private func directConfiguration(
    color: UIColor?,
    alpha: CGFloat,
    contentMode: UIView.ContentMode,
    objectValue: NSString?,
    scalarValue: CGFloat,
    enumValue: UIView.ContentMode,
    rectangleValue: CGRect,
    cornerRadius: CGFloat
  ) -> ViewConfiguration {
    ViewConfiguration(
      viewClass: AttributeTestView.self,
      attributes: [
        ViewConfiguration.Attribute(\AttributeTestView.backgroundColor, color),
        ViewConfiguration.Attribute(\AttributeTestView.alpha, alpha),
        ViewConfiguration.Attribute(\AttributeTestView.contentMode, contentMode),
        ViewConfiguration.Attribute(\AttributeTestView.objectValue, objectValue),
        ViewConfiguration.Attribute(\AttributeTestView.scalarValue, scalarValue),
        ViewConfiguration.Attribute(\AttributeTestView.enumValue, enumValue),
        ViewConfiguration.Attribute(\AttributeTestView.rectangleValue, rectangleValue),
      ],
      layerAttributes: [
        ViewConfiguration.LayerAttribute(\CALayer.cornerRadius, cornerRadius),
      ]
    )
  }

  private func valueCategoryConfiguration(
    objectValue: NSString?,
    scalarValue: CGFloat,
    enumValue: UIView.ContentMode,
    rectangleValue: CGRect,
    cornerRadius: CGFloat
  ) -> ViewConfiguration {
    ViewConfiguration(
      viewClass: AttributeTestView.self,
      attributes: [
        ViewConfiguration.Attribute(\AttributeTestView.objectValue, objectValue),
        ViewConfiguration.Attribute(\AttributeTestView.scalarValue, scalarValue),
        ViewConfiguration.Attribute(\AttributeTestView.enumValue, enumValue),
        ViewConfiguration.Attribute(\AttributeTestView.rectangleValue, rectangleValue),
      ],
      layerAttributes: [
        ViewConfiguration.LayerAttribute(\CALayer.cornerRadius, cornerRadius),
      ]
    )
  }

  private func optionalConfiguration(objectValue: NSString?, borderColor: CGColor?) -> ViewConfiguration {
    ViewConfiguration(
      viewClass: AttributeTestView.self,
      attributes: [
        ViewConfiguration.Attribute(\AttributeTestView.objectValue, objectValue),
      ],
      layerAttributes: [
        ViewConfiguration.LayerAttribute(\CALayer.borderColor, borderColor),
      ]
    )
  }

  private func tryUnwrapTapRecognizer(from view: UIView) -> UITapGestureRecognizer {
    guard let recognizer = view.gestureRecognizers?.first as? UITapGestureRecognizer else {
      XCTFail("Expected a tap gesture recognizer")
      return UITapGestureRecognizer()
    }
    return recognizer
  }

  private func invokeComponentKitGesture(_ recognizer: UIGestureRecognizer) {
    let sharedInstanceSelector = NSSelectorFromString("sharedInstance")
    let handleGestureSelector = NSSelectorFromString("handleGesture:")
    guard let forwarderClass = NSClassFromString("CKComponentGestureActionForwarder") as? NSObject.Type,
          let forwarder = forwarderClass.perform(sharedInstanceSelector)?.takeUnretainedValue() as? NSObject else {
      XCTFail("Expected to find ComponentKit's gesture action forwarder")
      return
    }
    _ = forwarder.perform(handleGestureSelector, with: recognizer)
  }
}
