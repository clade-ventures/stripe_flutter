import Flutter
import UIKit
import Stripe

public class SwiftStripeFlutterPlugin: NSObject, FlutterPlugin {
    
    static var flutterChannel: FlutterMethodChannel!
    static var customerContext: STPCustomerContext?
    
    static var delegateHandler: PaymentOptionViewControllerDelegate!
    static var applePayContextDelegate: ApplePayContextDelegate!
    
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "stripe_flutter", binaryMessenger: registrar.messenger())
    self.flutterChannel = channel
    let instance = SwiftStripeFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    
    let applePayDelegate = ApplePayContextDelegate(channel: channel)
    SwiftStripeFlutterPlugin.applePayContextDelegate = applePayDelegate
    
    self.delegateHandler = PaymentOptionViewControllerDelegate()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "sendPublishableKey":
        guard let args = call.arguments as? [String:Any] else {
            result(FlutterError(code: "InvalidArgumentsError", message: "Invalid arguments received", details: nil))
            return
        }
        guard let stripeKey = args["publishableKey"] as? String else {
            result(FlutterError(code: "InvalidArgumentsError", message: "Invalid arguments received", details: nil))
            return
        }
        let appleMerchantId = args["appleMerchantIdentifier"] as? String
        configurePaymentConfiguration(result, publishableKey: stripeKey, appleMerchantIdentifier: appleMerchantId)
        break
    case "initCustomerSession":
        initCustomerSession(result)
        break
    case "endCustomerSession":
        endCustomerSession(result);
        break;
    case "showPaymentMethodsScreen":
        showPaymentMethodsScreen(result);
        break;
    case "getCustomerDefaultSource":
        getDefaultSource(result)
        break
    case "getCustomerPaymentMethods":
        getCustomerPaymentMethods(result);
        break;
    case "isApplePaySupported":
        isApplePaySupported(result)
        break
    case "payUsingApplePay":
        guard let items = call.arguments as? [[String:String]] else {
            result(FlutterError(code: "InvalidArgumentsError", message: "Invalid items argument received", details: nil))
            return
        }
        handlePaymentUsingApplePay(result, items: items)
        break
    default:
        result(FlutterMethodNotImplemented)
    }
  }
    
    func configurePaymentConfiguration(_ result: @escaping FlutterResult, publishableKey: String, appleMerchantIdentifier: String?) {
        STPAPIClient.shared().publishableKey = publishableKey
        if let appleMerchantId = appleMerchantIdentifier {
            STPPaymentConfiguration.shared().appleMerchantIdentifier = appleMerchantId
        }
        result(nil)
    }
    
    func initCustomerSession(_ result: @escaping FlutterResult) {
        let flutterEphemeralKeyProvider = FlutterEphemeralKeyProvider(channel: SwiftStripeFlutterPlugin.flutterChannel)
        SwiftStripeFlutterPlugin.customerContext = STPCustomerContext(keyProvider: flutterEphemeralKeyProvider)
        result(nil)
    }
    
    func endCustomerSession(_ result: @escaping FlutterResult) {
        SwiftStripeFlutterPlugin.customerContext?.clearCache()
        SwiftStripeFlutterPlugin.customerContext = nil
        
        result(nil)
    }
    
    func getCustomerPaymentMethods(_ result: @escaping FlutterResult) {
        guard let context = SwiftStripeFlutterPlugin.customerContext else {
            result(FlutterError(code: "IllegalStateError",
                                message: "CustomerSession is not properly initialized, have you correctly initialize CustomerSession?",
                                details: nil))
            return
        }
        
        context.listPaymentMethodsForCustomer { (paymentMethods, error) in
            if let err = error {
                result(FlutterError(code: "FailedRetrievePayementMethods", message: err.localizedDescription, details: nil))
                return
            }
            if let list = paymentMethods {
                result(list.map({ (method) in
                    return parsePaymentMethod(method)
                }))
            } else {
                result([])
            }
        }
    }
    
    func getDefaultSource(_ result: @escaping FlutterResult) {
        guard let context = SwiftStripeFlutterPlugin.customerContext else {
            result(FlutterError(code: "IllegalStateError",
                                message: "CustomerSession is not properly initialized, have you correctly initialize CustomerSession?",
                                details: nil))
            return
        }
        context.retrieveCustomer({ (customer,  error) in
            if error != nil {
                result(FlutterError(code: "StripeDefaultSource", message: error?.localizedDescription, details: nil))
                return
            }
            if let source = customer?.defaultSource as? STPSource {
                var tuppleResult = [String:Any?]()
                tuppleResult["id"] = source.stripeID
                tuppleResult["last4"] = source.cardDetails?.last4
                tuppleResult["brand"] = STPCard.string(from: source.cardDetails?.brand ?? STPCardBrand.unknown)
                tuppleResult["expiredYear"] = Int(source.cardDetails?.expYear ?? 0)
                tuppleResult["expiredMonth"] = Int(source.cardDetails?.expMonth ?? 0)
                result(tuppleResult)
            } else if let card = customer?.defaultSource as? STPCard {
                var tuppleResult = [String:Any?]()
                tuppleResult["id"] = card.stripeID
                tuppleResult["last4"] = card.last4
                tuppleResult["brand"] = STPCard.string(from: card.brand)
                tuppleResult["expiredYear"] = Int(card.expYear)
                tuppleResult["expiredMonth"] = Int(card.expMonth)
            } else {
                if let s = customer?.defaultSource {
                    result(s.description)
                    return
                } else {
                    result(nil)
                }
            }
        })
    }
    
    func showPaymentMethodsScreen(_ result: @escaping FlutterResult) {
        guard let _context = SwiftStripeFlutterPlugin.customerContext else {
            result(FlutterError(code: "IllegalStateError",
                                message: "CustomerSession is not properly initialized, have you correctly initialize CustomerSession?",
                                details: nil))
            return
        }
        if let uiAppDelegate = UIApplication.shared.delegate,
            let tempWindow = uiAppDelegate.window,
            let window = tempWindow,
            let rootVc = window.rootViewController {
            
            SwiftStripeFlutterPlugin.delegateHandler.window = window
            SwiftStripeFlutterPlugin.delegateHandler.flutterViewController = rootVc
            SwiftStripeFlutterPlugin.delegateHandler.setFlutterResult(result)

            let vc = STPPaymentOptionsViewController(configuration: STPPaymentConfiguration.shared(),
                                                     theme: STPTheme.default(),
                                                     customerContext: _context,
                                                     delegate: SwiftStripeFlutterPlugin.delegateHandler)
            
            let uiNavController = UINavigationController(rootViewController: vc)
            
            UIView.transition(with: window, duration: 0.2, options: .transitionCrossDissolve, animations: {
                window.rootViewController = uiNavController
            }, completion: nil)
            
            window.rootViewController = uiNavController
            return
        } else {
            result(FlutterError(code: "IllegalStateError",
                                message: "Root ViewController in Window is currently not available.",
                                details: nil))
            
            return
        }
    }
    
    func isApplePaySupported(_ result: @escaping FlutterResult) {
        result(Stripe.deviceSupportsApplePay())
    }
    
    func handlePaymentUsingApplePay(_ result: @escaping FlutterResult, items: [[String:String]]) {
        guard let merchantId = STPPaymentConfiguration.shared().appleMerchantIdentifier else { return }
        
        if  let uiAppDelegate = UIApplication.shared.delegate,
            let tempWindow = uiAppDelegate.window,
            let window = tempWindow,
            let rootVc = window.rootViewController {
            
            let paymentRequest = Stripe.paymentRequest(withMerchantIdentifier: merchantId, country: "AU", currency: "AUD")
            
            // prepare sumarry items
            paymentRequest.paymentSummaryItems = items.compactMap(){(item) -> PKPaymentSummaryItem? in
                if  let label = item["label"],
                    let strAmount = item["amount"] {
                    return PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(string: strAmount))
                }
                return nil
            }
            
            if let applePayContext = STPApplePayContext(paymentRequest: paymentRequest, delegate: SwiftStripeFlutterPlugin.applePayContextDelegate) {
                // Present Apple Pay payment sheet
                SwiftStripeFlutterPlugin.applePayContextDelegate.setFlutterResult(result)
                applePayContext.presentApplePay(on: rootVc)
            } else {
                // There is a problem with your Apple Pay configuration
            }
        }
    }
}

class FlutterEphemeralKeyProvider : NSObject, STPCustomerEphemeralKeyProvider {
    
    private let channel: FlutterMethodChannel
    
    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }
    
    func createCustomerKey(withAPIVersion apiVersion: String, completion: @escaping STPJSONResponseCompletionBlock) {
        var args = [String:Any?]()
        args["apiVersion"] = apiVersion
        channel.invokeMethod("getEphemeralKey", arguments: args, result: { result in
            let json = result as? String
            
            guard let _json = json else {
                completion(nil, CastMismatchError())
                return
            }
            
            guard let data = _json.data(using: .utf8) else {
                completion(nil, InternalStripeError())
                return
            }
            
            guard let dictionary = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: AnyObject] else {
                completion(nil, InternalStripeError())
                return
            }
            
            guard let _dict = dictionary else {
                completion(nil, InternalStripeError())
                return
            }
            
            completion(_dict, nil)
        })
    }
}

class ApplePayContextDelegate: NSObject, STPApplePayContextDelegate {
    private let channel: FlutterMethodChannel
    private var flutterResult: FlutterResult? = nil
    private var argument: [String: String]? = nil
    
    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }
    
    func setFlutterResult(_ result: @escaping FlutterResult) {
        self.flutterResult = result
    }
    
    func applePayContext(_ context: STPApplePayContext, didCreatePaymentMethod paymentMethod: STPPaymentMethod, completion: @escaping STPIntentClientSecretCompletionBlock) {

        // Call backend to create and confirm a PaymentIntent and get its client secret
        let args = parsePaymentMethod(paymentMethod)
        channel.invokeMethod("doNativePaymentCheckout", arguments: args, result: { rawResult in
            guard let result = rawResult as? [String:Any] else {
                completion(nil, NSError(domain: "invalid_result", code: 500, userInfo: ["NSLocalizedDescriptionKey": "invalid fetchClientSecret result"]))
                return
            }
            
            if let isSuccess = result["isSuccess"] as? Bool {
                if !isSuccess {
                    if let message = result["errorMessage"] as? String {
                        completion(nil, NSError(domain: "failed", code: 500, userInfo: ["NSLocalizedDescriptionKey": message]))
                    } else {
                        completion(nil, NSError(domain: "failed", code: 500, userInfo: ["NSLocalizedDescriptionKey": "failed when fetch client secret"]))
                    }
                    return
                }
            }
                        
            guard let clientSecret = result["clientSecret"] as? String else {
                completion(nil, NSError(domain: "invalid_clientSecret", code: 500, userInfo: ["NSLocalizedDescriptionKey": "invalid clientSecret result"]))
                return
            }
            
            if let argument = result["argument"] as? [String:String] {
                self.argument = argument
            } else {
                self.argument = nil
            }
            
            // Call the completion block with the client secret or an error
            completion(clientSecret, nil)
        })
    }
    
    func applePayContext(_ context: STPApplePayContext, didCompleteWith status: STPPaymentStatus, error: Error?) {
        var resultArgs : [String : Any?] = ["success": false]
        switch status {
            case .success:
                resultArgs = ["success": true, "arg": argument]
                self.flutterResult?(resultArgs)
                break
            case .error:
                // Payment failed, show the error
                self.flutterResult?(FlutterError(code: "ApplePayError", message: error?.localizedDescription, details: nil))
                break
            case .userCancellation:
                // User cancelled the payment
                self.flutterResult?(resultArgs)
                break
            @unknown default:
                self.flutterResult?(resultArgs)
        }
    }
}

class PaymentOptionViewControllerDelegate: NSObject,  STPPaymentOptionsViewControllerDelegate {
    
    private var currentPaymentMethod: STPPaymentOption? = nil
    private var flutterResult: FlutterResult? = nil
    private var tuppleResult = [String:Any?]()
    
    var flutterViewController: UIViewController?
    var window: UIWindow?
    
    func setFlutterResult(_ result: @escaping FlutterResult) {
        self.flutterResult = result
    }
    
    func paymentOptionsViewController(_ paymentOptionsViewController: STPPaymentOptionsViewController, didSelect paymentOption: STPPaymentOption) {
        tuppleResult = [String:Any?]()
        currentPaymentMethod = paymentOption
        print(paymentOption)
        if let source = paymentOption as? STPPaymentMethod {
            tuppleResult = parsePaymentMethod(source)
        } else if let applePay = paymentOption as? STPApplePayPaymentOption {
            tuppleResult["label"] = applePay.label
            tuppleResult["type"] = "ApplePay"
        }
    }
    
    func paymentOptionsViewController(_ paymentOptionsViewController: STPPaymentOptionsViewController, didFailToLoadWithError error: Error) {
        self.flutterResult?(FlutterError(code: "PaymentOptionsError", message: error.localizedDescription, details: nil))
        closeWindow()
        cleanInstance()
    }
    
    func paymentOptionsViewControllerDidFinish(_ paymentOptionsViewController: STPPaymentOptionsViewController) {
        print(tuppleResult)
        self.flutterResult?(tuppleResult)
        closeWindow()
        cleanInstance()
    }
    
    func paymentOptionsViewControllerDidCancel(_ paymentOptionsViewController: STPPaymentOptionsViewController) {
        self.flutterResult?(nil)
        closeWindow()
        cleanInstance()
    }
    
    private func closeWindow() {
        if let _window = window, let vc = flutterViewController {
            UIView.transition(with: _window, duration: 0.2, options: .transitionCrossDissolve, animations: {
                _window.rootViewController = vc
            }, completion: nil)
        }
    }
    
    private func cleanInstance() {
        flutterViewController = nil
        window = nil
    }
    
}

class CastMismatchError : Error {
    
}

class InternalStripeError : Error {
    
}

func parsePaymentMethod(_ paymentMethod: STPPaymentMethod) -> [String:Any?] {
    var tuppleResult = [String:Any?]()
    tuppleResult["id"] = paymentMethod.stripeId
    tuppleResult["last4"] = paymentMethod.card?.last4
    tuppleResult["brand"] = STPCard.string(from: paymentMethod.card?.brand ?? STPCardBrand.unknown)
    tuppleResult["expiredYear"] = Int(paymentMethod.card?.expYear ?? 0)
    tuppleResult["expiredMonth"] = Int(paymentMethod.card?.expMonth ?? 0)
    tuppleResult["type"] = "Card"
    return tuppleResult
}
