//
// Copyright (c) 2021 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

import Adyen
import Foundation
import UIKit

/// A component that provides a form for BLIK payments.
public final class BLIKComponent: PaymentComponent, PresentableComponent, Localizable, LoadingComponent {
    /// :nodoc:
    public var paymentMethod: PaymentMethod { blikPaymentMethod }

    /// :nodoc:
    public weak var delegate: PaymentComponentDelegate?

    /// :nodoc:
    public lazy var viewController: UIViewController = SecuredViewController(child: formViewController, style: style)

    /// :nodoc:
    public var localizationParameters: LocalizationParameters?

    /// Describes the component's UI style.
    public let style: FormComponentStyle

    /// :nodoc:
    public let requiresModalPresentation: Bool = true

    /// :nodoc:
    private let blikPaymentMethod: BLIKPaymentMethod

    /// Initializes the BLIK component.
    ///
    /// - Parameter paymentMethod: The BLIK payment method.
    /// - Parameter style: The Component's UI style.
    public init(paymentMethod: BLIKPaymentMethod, style: FormComponentStyle = FormComponentStyle()) {
        self.blikPaymentMethod = paymentMethod
        self.style = style
    }

    /// :nodoc:
    public func stopLoading() {
        button.showsActivityIndicator = false
        formViewController.view.isUserInteractionEnabled = true
    }

    private lazy var formViewController: FormViewController = {
        let formViewController = FormViewController(style: style)
        formViewController.localizationParameters = localizationParameters
        formViewController.delegate = self

        formViewController.title = paymentMethod.name.uppercased()

        formViewController.append(hintLabelItem.withPadding(padding: .init(top: 7, left: 0, bottom: -7, right: 0)))
        formViewController.append(codeItem)
        formViewController.append(button.withPadding(padding: .init(top: 8, left: 0, bottom: -16, right: 0)))

        return formViewController
    }()

    /// The helper message item.
    internal lazy var hintLabelItem: FormLabelItem = {
        FormLabelItem(text: localizedString(.blikHelp, localizationParameters),
                      style: style.hintLabel,
                      identifier: ViewIdentifierBuilder.build(scopeInstance: self, postfix: "blikCodeHintLabel"))
    }()

    /// The BLIK code item.
    internal lazy var codeItem: FormTextInputItem = {
        let item = FormTextInputItem(style: style.textField)
        item.title = localizedString(.blikCode, localizationParameters)
        item.placeholder = localizedString(.blikPlaceholder, localizationParameters)
        item.validator = NumericStringValidator(minimumLength: 6, maximumLength: 6)
        item.formatter = NumericFormatter()
        item.validationFailureMessage = localizedString(.blikInvalid, localizationParameters)
        item.keyboardType = .numberPad
        item.identifier = ViewIdentifierBuilder.build(scopeInstance: self, postfix: "blikCodeItem")
        return item
    }()

    /// The footer item.
    internal lazy var button: FormButtonItem = {
        let item = FormButtonItem(style: style.mainButtonItem)
        item.identifier = ViewIdentifierBuilder.build(scopeInstance: self, postfix: "payButtonItem")
        item.title = localizedSubmitButtonTitle(with: payment?.amount,
                                                style: .immediate,
                                                localizationParameters)
        item.buttonSelectionHandler = { [weak self] in
            self?.didSelectSubmitButton()
        }
        return item
    }()

    private func didSelectSubmitButton() {
        guard formViewController.validate() else { return }

        let details = BLIKDetails(paymentMethod: paymentMethod,
                                  blikCode: codeItem.value)
        button.showsActivityIndicator = true
        formViewController.view.isUserInteractionEnabled = false

        submit(data: PaymentComponentData(paymentMethodDetails: details))
    }
}

extension BLIKComponent: TrackableComponent {}
