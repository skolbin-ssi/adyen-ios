//
// Copyright (c) 2021 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

import Adyen
#if canImport(AdyenComponents)
    import AdyenComponents
#endif
#if canImport(AdyenActions)
    import AdyenActions
#endif
import UIKit

/// A component that handles the entire flow of payment selection and payment details entry.
public final class DropInComponent: NSObject, PresentableComponent {

    private let configuration: PaymentMethodsConfiguration

    private var paymentInProgress: Bool = false

    private var selectedPaymentComponent: PaymentComponent?

    /// The payment methods to display.
    public let paymentMethods: PaymentMethods
    
    /// The delegate of the drop in component.
    public weak var delegate: DropInComponentDelegate?
    
    /// Indicates the UI configuration of the drop in component.
    public let style: Style
    
    /// The title text on the first page of drop in component.
    public let title: String
    
    /// Initializes the drop in component.
    ///
    /// - Parameters:
    ///   - paymentMethods: The payment methods to display.
    ///   - paymentMethodsConfiguration: The payment method specific configuration.
    ///   - style: The UI styles of the components.
    ///   - title: Name of the application. To be displayed on a firstpayment page.
    ///            If no external value provided, the Main Bundle's name would be used.
    public init(paymentMethods: PaymentMethods,
                paymentMethodsConfiguration: PaymentMethodsConfiguration,
                style: Style = Style(),
                title: String? = nil) {
        self.title = title ?? Bundle.main.displayName
        self.configuration = paymentMethodsConfiguration
        self.paymentMethods = paymentMethods
        self.style = style
        super.init()
    }
    
    // MARK: - Presentable Component Protocol
    
    /// :nodoc:
    public var viewController: UIViewController {
        navigationController
    }

    // MARK: - Handling Actions

    /// Handles an action to complete a payment.
    ///
    /// - Parameter action: The action to handle.
    public func handle(_ action: Action) {
        actionComponent.handle(action)
    }
    
    // MARK: - Private

    private lazy var componentManager = ComponentManager(paymentMethods: paymentMethods,
                                                         configuration: configuration,
                                                         style: style)
    
    private lazy var rootComponent: PresentableComponent & ComponentLoader = {
        if let preselectedComponents = componentManager.components.stored.first {
            return preselectedPaymentMethodComponent(for: preselectedComponents)
        } else {
            return paymentMethodListComponent()
        }
    }()
    
    private lazy var navigationController = DropInNavigationController(rootComponent: rootComponent,
                                                                       style: style.navigation,
                                                                       cancelHandler: { [weak self] isRoot, component in
                                                                           self?.didSelectCancelButton(isRoot: isRoot,
                                                                                                       component: component)
                                                                       })

    private lazy var actionComponent: AdyenActionComponent = {
        let handler = AdyenActionComponent()
        handler._isDropIn = true
        handler.environment = environment
        handler.clientKey = configuration.clientKey
        handler.redirectComponentStyle = style.redirectComponent
        handler.delegate = self
        handler.presentationDelegate = self
        handler.localizationParameters = configuration.localizationParameters
        return handler
    }()
    
    private func paymentMethodListComponent() -> PaymentMethodListComponent {
        let paymentComponents = componentManager.components
        let component = PaymentMethodListComponent(components: paymentComponents, style: style.listComponent)
        component.localizationParameters = configuration.localizationParameters
        component.delegate = self
        component._isDropIn = true
        component.environment = environment
        return component
    }
    
    private func preselectedPaymentMethodComponent(for storedPaymentComponent: PaymentComponent) -> PreselectedPaymentMethodComponent {
        let component = PreselectedPaymentMethodComponent(component: storedPaymentComponent,
                                                          title: title,
                                                          style: style.formComponent,
                                                          listItemStyle: style.listComponent.listItem)
        component.payment = configuration.payment
        component.localizationParameters = configuration.localizationParameters
        component.delegate = self
        component._isDropIn = true
        component.environment = environment
        return component
    }
    
    private func didSelect(_ component: PaymentComponent) {
        selectedPaymentComponent = component
        component.delegate = self
        component._isDropIn = true
        component.environment = environment
        
        switch component {
        case let component as PreApplePayComponent:
            component.presentationDelegate = self
            navigationController.present(asModal: component)
        case let component as PresentableComponent where component.requiresModalPresentation:
            navigationController.present(asModal: component)
        case let component as PresentableComponent where component.viewController is UIAlertController:
            navigationController.present(component.viewController, customPresentation: false)
        case let component as PresentableComponent:
            navigationController.present(component.viewController, customPresentation: true)
        case let component as EmptyPaymentComponent:
            component.initiatePayment()
        default:
            break
        }
    }
    
    private func didSelectCancelButton(isRoot: Bool, component: PresentableComponent) {
        guard !paymentInProgress || component is Cancellable else { return }
        
        if isRoot {
            self.delegate?.didFail(with: ComponentError.cancelled, from: self)
        } else {
            navigationController.popViewController(animated: true)
            userDidCancel(component)
        }
    }

    private func userDidCancel(_ component: Component) {
        stopLoading()
        component.cancelIfNeeded()

        if let component = (component as? PaymentComponent) ?? selectedPaymentComponent, paymentInProgress {
            delegate?.didCancel(component: component, from: self)
        }

        paymentInProgress = false
    }

    /// :nodoc:
    private func stopLoading() {
        rootComponent.stopLoading()
        selectedPaymentComponent?.stopLoadingIfNeeded()
    }
}

/// :nodoc:
extension DropInComponent: PaymentMethodListComponentDelegate {
    
    /// :nodoc:
    internal func didSelect(_ component: PaymentComponent, in paymentMethodListComponent: PaymentMethodListComponent) {
        rootComponent.startLoading(for: component)
        didSelect(component)
    }
    
}

/// :nodoc:
extension DropInComponent: PaymentComponentDelegate {
    
    /// :nodoc:
    public func didSubmit(_ data: PaymentComponentData, from component: PaymentComponent) {
        paymentInProgress = true
        delegate?.didSubmit(data, for: component.paymentMethod, from: self)
    }
    
    /// :nodoc:
    public func didFail(with error: Error, from component: PaymentComponent) {
        if case ComponentError.cancelled = error {
            userDidCancel(component)
        } else {
            delegate?.didFail(with: error, from: self)
        }
    }

}

/// :nodoc:
extension DropInComponent: ActionComponentDelegate {
    
    /// :nodoc:
    public func didOpenExternalApplication(_ component: ActionComponent) {
        stopLoading()
    }

    /// :nodoc:
    public func didComplete(from component: ActionComponent) {
        delegate?.didComplete(from: self)
    }
    
    /// :nodoc:
    public func didFail(with error: Error, from component: ActionComponent) {
        if case ComponentError.cancelled = error {
            userDidCancel(component)
        } else {
            delegate?.didFail(with: error, from: self)
        }
    }
    
    /// :nodoc:
    public func didProvide(_ data: ActionComponentData, from component: ActionComponent) {
        delegate?.didProvide(data, from: self)
    }
    
}

extension DropInComponent: PreselectedPaymentMethodComponentDelegate {

    internal func didProceed(with component: PaymentComponent) {
        rootComponent.startLoading(for: component)
        
        guard let storedPaymentMethod = component.paymentMethod as? StoredPaymentMethod else {
            return didSelect(component)
        }
        
        if storedPaymentMethod is StoredCardPaymentMethod {
            return didSelect(component)
        }
        
        let details = StoredPaymentDetails(paymentMethod: storedPaymentMethod)
        self.delegate?.didSubmit(PaymentComponentData(paymentMethodDetails: details), for: storedPaymentMethod, from: self)
    }
    
    internal func didRequestAllPaymentMethods() {
        let newRoot = paymentMethodListComponent()
        navigationController.present(root: newRoot)
        rootComponent = newRoot
    }
}

extension DropInComponent: PresentationDelegate {

    public func present(component: PresentableComponent) {
        navigationController.present(asModal: component)
    }
}

extension DropInComponent: FinalizableComponent {

    /// Stops loading and finalise DropIn's selected payment if nececery.
    /// This method must be called after certan payment methods (e.x. ApplePay)
    /// - Parameter success: Status of the payment.
    public func didFinalize(with success: Bool) {
        stopLoading()
        selectedPaymentComponent?.finalizeIfNeeded(with: success)
    }
}

private extension Bundle {

    // Name of the app - title under the icon.
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
    }

}
