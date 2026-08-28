/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

import ComponentKit
import UIKit

private extension KeyPath where Root: NSObject {
  var asString: String {
    return NSExpression(forKeyPath: self).keyPath
  }
}

/// Gives RenderCore an Objective-C object with Swift value equality semantics.
/// Values that do not conform to `Equatable` intentionally compare unequal so
/// their applicators are rerun conservatively.
private final class ReconciledAttributeValue: NSObject {
  private let value: Any
  private let valuesAreEqual: (Any) -> Bool

  init<Value>(_ value: Value) {
    self.value = value
    valuesAreEqual = { _ in false }
  }

  init<Value: Equatable>(_ value: Value, usingEquality: Bool) {
    self.value = value
    valuesAreEqual = { otherValue in
      guard let otherValue = otherValue as? Value else {
        return false
      }
      return value == otherValue
    }
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? ReconciledAttributeValue else {
      return false
    }
    return valuesAreEqual(other.value)
  }

  // RenderCore previously used the same @YES value for every Swift attribute,
  // so retaining a constant hash preserves that behavior while isEqual(_:) now
  // distinguishes values.
  override var hash: Int {
    return 0
  }
}

/// Represents the class of a view and the attributes that should be applied to it.
public struct ViewConfiguration {
  /// Represents a view configuration attribute.
  public struct Attribute<View: UIView> {
    /// The Objective-C bridgeable type.
    let componentViewAttribute: ComponentViewAttributeSwiftBridge

    /// Creates a new attribute.
    /// - Parameters:
    ///   - keyPath: The keypath where the value should be stored.
    ///   - value: The value to store.
    public init<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<View, Value>, _ value: Value) {
      self.init(keyPath, value, reconciliationValue: ReconciledAttributeValue(value, usingEquality: true))
    }

    /// Creates an attribute for a value without meaningful equality semantics.
    /// Such values are conservatively reapplied during reconciliation.
    public init<Value>(_ keyPath: ReferenceWritableKeyPath<View, Value>, _ value: Value) {
      self.init(keyPath, value, reconciliationValue: ReconciledAttributeValue(value))
    }

    private init<Value>(
      _ keyPath: ReferenceWritableKeyPath<View, Value>,
      _ value: Value,
      reconciliationValue: ReconciledAttributeValue
    ) {
      componentViewAttribute = ComponentViewAttributeSwiftBridge(identifier: keyPath.asString, value: reconciliationValue) { v in
        let view = v as! View
        view[keyPath: keyPath] = value
      }
    }

    /// Creates a new attribute
    /// - Parameter componentViewAttribute: The bridged view attribute.
    init(componentViewAttribute: ComponentViewAttributeSwiftBridge) {
      self.componentViewAttribute = componentViewAttribute
    }
  }

  /// Represents a view configuration layer attribute.
  public struct LayerAttribute {
    /// The Objective-C bridgeable type.
    let componentViewAttribute: ComponentViewAttributeSwiftBridge

    /// Creates a new layer attribute.
    /// - Parameters:
    ///   - keyPath: The keypath where the value should be stored.
    ///   - value: The value to store.
    public init<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<CALayer, Value>, _ value: Value) {
      self.init(keyPath, value, reconciliationValue: ReconciledAttributeValue(value, usingEquality: true))
    }

    /// Creates a layer attribute for a value without meaningful equality semantics.
    /// Such values are conservatively reapplied during reconciliation.
    public init<Value>(_ keyPath: ReferenceWritableKeyPath<CALayer, Value>, _ value: Value) {
      self.init(keyPath, value, reconciliationValue: ReconciledAttributeValue(value))
    }

    private init<Value>(
      _ keyPath: ReferenceWritableKeyPath<CALayer, Value>,
      _ value: Value,
      reconciliationValue: ReconciledAttributeValue
    ) {
      componentViewAttribute = ComponentViewAttributeSwiftBridge(identifier: "layer" + keyPath.asString, value: reconciliationValue) { view in
        view.layer[keyPath: keyPath] = value
      }
    }
  }

  /// The Objective-C bridgeable type.
  public let viewConfiguration: ComponentViewConfigurationSwiftBridge

  /// Creates a new configuration.
  /// - Parameters:
  ///   - viewClass: The view class to use.
  ///   - attributes: The view attributes.
  ///   - layerAttributes: The layer attribues.
  public init<View: UIView>(viewClass: View.Type, attributes: [Attribute<View>] = [], layerAttributes: [LayerAttribute] = []) {
    viewConfiguration = ComponentViewConfigurationSwiftBridge(viewClass: viewClass,
                                                              attributes: attributes.map { $0.componentViewAttribute } + layerAttributes.map { $0.componentViewAttribute })
  }

#if swift(>=5.1)
  /// Creates a new configuration.
  /// - Parameters:
  ///   - viewClass: The view class to use.
  ///   - attributes: The view/layer attributes.
  public init<View: UIView>(viewClass: View.Type, @ViewConfigurationAttributeBuilder<View> attributes: () -> [ComponentViewAttributeSwiftBridge]) {
    viewConfiguration = ComponentViewConfigurationSwiftBridge(viewClass: viewClass, attributes: attributes())
  }
#endif
}

#if swift(>=5.1)
@_functionBuilder
public struct ViewConfigurationAttributeBuilder<View: UIView> {
  public enum Directive {
    case attribute(ViewConfiguration.Attribute<View>)
    case layerAttribute(ViewConfiguration.LayerAttribute)

    fileprivate var swiftBridge: ComponentViewAttributeSwiftBridge {
      switch self {
      case let .attribute(attribute):
        return attribute.componentViewAttribute
      case let .layerAttribute(attribute):
        return attribute.componentViewAttribute
      }
    }
  }

  #if swift(<5.3)
  public static func buildBlock(_ parts: Directive...) -> [ComponentViewAttributeSwiftBridge] {
    parts.map { $0.swiftBridge }
  }
  #endif

  public static func buildBlock(_ parts: Directive...) -> [Directive] {
    parts
  }

  public static func buildFinalResult(_ parts: [Directive]) -> [Directive] {
    parts
  }

  public static func buildFinalResult(_ parts: [Directive]) -> [ComponentViewAttributeSwiftBridge] {
    parts.map { $0.swiftBridge }
  }

  public static func buildExpression(_ attr: ViewConfiguration.Attribute<View>) -> Directive {
    .attribute(attr)
  }

  public static func buildExpression(_ attr: ViewConfiguration.LayerAttribute) -> Directive {
    .layerAttribute(attr)
  }

  public static func buildExpression<Value>(_ attr: (key: ReferenceWritableKeyPath<View, Value>, value: Value)) -> Directive {
    .attribute(ViewConfiguration.Attribute<View>(attr.key, attr.value))
  }

  public static func buildExpression<Value>(_ attr: (key: ReferenceWritableKeyPath<CALayer, Value>, value: Value)) -> Directive {
    .layerAttribute(ViewConfiguration.LayerAttribute(attr.key, attr.value))
  }
}

#endif
