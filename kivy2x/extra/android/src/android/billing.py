'''
Android Billing API (V6/V7)
===========================

Modern Google Play Billing Library implementation using pyjnius.
'''

from jnius import autoclass, PythonJavaClass, java_method
from android import mActivity
from kivy.clock import Clock
from kivy.logger import Logger

# Java Classes
BillingClient = autoclass('com.android.billingclient.api.BillingClient')
BillingClientBuilder = autoclass('com.android.billingclient.api.BillingClient$Builder')
BillingFlowParams = autoclass('com.android.billingclient.api.BillingFlowParams')
BillingFlowProductParams = autoclass('com.android.billingclient.api.BillingFlowParams$ProductDetailsParams')
QueryProductDetailsParams = autoclass('com.android.billingclient.api.QueryProductDetailsParams')
ProductParams = autoclass('com.android.billingclient.api.QueryProductDetailsParams$Product')
ProductType = autoclass('com.android.billingclient.api.BillingClient$ProductType')
AcknowledgePurchaseParams = autoclass('com.android.billingclient.api.AcknowledgePurchaseParams')
ConsumeParams = autoclass('com.android.billingclient.api.ConsumeParams')
BillingResponseCode = autoclass('com.android.billingclient.api.BillingClient$BillingResponseCode')
ArrayList = autoclass('java.util.ArrayList')


class PurchasesUpdatedListener(PythonJavaClass):
    __javainterfaces__ = ['com/android/billingclient/api/PurchasesUpdatedListener']
    __javacontext__ = 'app'

    def __init__(self, callback):
        super(PurchasesUpdatedListener, self).__init__()
        self.callback = callback

    @java_method('(Lcom/android/billingclient/api/BillingResult;Ljava/util/List;)V')
    def onPurchasesUpdated(self, billingResult, purchases):
        if self.callback:
            self.callback(billingResult, purchases)


class BillingClientStateListener(PythonJavaClass):
    __javainterfaces__ = ['com/android/billingclient/api/BillingClientStateListener']
    __javacontext__ = 'app'

    def __init__(self, on_setup_finished, on_disconnected):
        super(BillingClientStateListener, self).__init__()
        self.on_setup_finished = on_setup_finished
        self.on_disconnected = on_disconnected

    @java_method('(Lcom/android/billingclient/api/BillingResult;)V')
    def onBillingSetupFinished(self, billingResult):
        if self.on_setup_finished:
            self.on_setup_finished(billingResult)

    @java_method('()V')
    def onBillingServiceDisconnected(self):
        if self.on_disconnected:
            self.on_disconnected()


class ProductDetailsResponseListener(PythonJavaClass):
    __javainterfaces__ = ['com/android/billingclient/api/ProductDetailsResponseListener']
    __javacontext__ = 'app'

    def __init__(self, callback):
        super(ProductDetailsResponseListener, self).__init__()
        self.callback = callback

    @java_method('(Lcom/android/billingclient/api/BillingResult;Ljava/util/List;)V')
    def onProductDetailsResponse(self, billingResult, productDetailsList):
        if self.callback:
            self.callback(billingResult, productDetailsList)


class AcknowledgePurchaseResponseListener(PythonJavaClass):
    __javainterfaces__ = ['com/android/billingclient/api/AcknowledgePurchaseResponseListener']
    __javacontext__ = 'app'

    def __init__(self, callback):
        super(AcknowledgePurchaseResponseListener, self).__init__()
        self.callback = callback

    @java_method('(Lcom/android/billingclient/api/BillingResult;)V')
    def onAcknowledgePurchaseResponse(self, billingResult):
        if self.callback:
            self.callback(billingResult)


class ConsumeResponseListener(PythonJavaClass):
    __javainterfaces__ = ['com/android/billingclient/api/ConsumeResponseListener']
    __javacontext__ = 'app'

    def __init__(self, callback):
        super(ConsumeResponseListener, self).__init__()
        self.callback = callback

    @java_method('(Lcom/android/billingclient/api/BillingResult;Ljava/lang/String;)V')
    def onConsumeResponse(self, billingResult, purchaseToken):
        if self.callback:
            self.callback(billingResult, purchaseToken)


class BillingService:
    """
    A pure-Python wrapper over Google Play Billing Library V6/V7.
    """
    
    def __init__(self):
        self.client = None
        self._purchases_listener = PurchasesUpdatedListener(self._on_purchases_updated)
        self.is_connected = False
        self._on_connected_callback = None
        self.product_details_cache = {}
        
        self.on_purchase_success = None
        self.on_purchase_error = None

    def start_connection(self, on_connected_callback=None):
        self._on_connected_callback = on_connected_callback
        builder = BillingClient.newBuilder(mActivity)
        builder.setListener(self._purchases_listener)
        builder.enablePendingPurchases()
        self.client = builder.build()
        
        self._state_listener = BillingClientStateListener(
            self._on_setup_finished,
            self._on_disconnected
        )
        self.client.startConnection(self._state_listener)

    def _on_setup_finished(self, billing_result):
        code = billing_result.getResponseCode()
        if code == BillingResponseCode.OK:
            Logger.info("BillingService: Connected to Google Play Billing.")
            self.is_connected = True
            if self._on_connected_callback:
                Clock.schedule_once(lambda dt: self._on_connected_callback(True))
        else:
            Logger.error(f"BillingService: Setup failed with code {code}.")
            if self._on_connected_callback:
                Clock.schedule_once(lambda dt: self._on_connected_callback(False))

    def _on_disconnected(self):
        Logger.info("BillingService: Disconnected from Google Play Billing.")
        self.is_connected = False

    def query_products(self, product_ids, product_type='inapp', callback=None):
        """
        Query product prices and details.
        product_type: 'inapp' or 'subs'
        """
        if not self.is_connected:
            Logger.error("BillingService: Cannot query products, not connected.")
            if callback:
                callback([])
            return

        product_list = ArrayList()
        ptype = ProductType.INAPP if product_type == 'inapp' else ProductType.SUBS
        
        for pid in product_ids:
            product_params = ProductParams.newBuilder() \
                .setProductId(pid) \
                .setProductType(ptype) \
                .build()
            product_list.add(product_params)
            
        params = QueryProductDetailsParams.newBuilder().setProductList(product_list).build()
        
        def handle_response(billing_result, product_details_list):
            results = []
            if billing_result.getResponseCode() == BillingResponseCode.OK and product_details_list:
                for i in range(product_details_list.size()):
                    details = product_details_list.get(i)
                    pid = details.getProductId()
                    self.product_details_cache[pid] = details
                    results.append({
                        'id': pid,
                        'name': details.getName(),
                        'description': details.getDescription(),
                        'type': details.getProductType()
                    })
            if callback:
                Clock.schedule_once(lambda dt: callback(results))

        listener = ProductDetailsResponseListener(handle_response)
        self.client.queryProductDetailsAsync(params, listener)

    def buy(self, product_id):
        """
        Launch the purchase flow for a specific product_id.
        Ensure you have queried it via query_products first.
        """
        if not self.is_connected:
            Logger.error("BillingService: Cannot buy, not connected.")
            return False
            
        details = self.product_details_cache.get(product_id)
        if not details:
            Logger.error(f"BillingService: Product {product_id} not queried or invalid.")
            return False

        flow_product_params = BillingFlowProductParams.newBuilder().setProductDetails(details)
            
        ptype = details.getProductType()
        if ptype == ProductType.SUBS:
            offers = details.getSubscriptionOfferDetails()
            if offers and offers.size() > 0:
                offer = offers.get(0)
                flow_product_params.setOfferToken(offer.getOfferToken())
                
        product_params_list = ArrayList()
        product_params_list.add(flow_product_params.build())

        flow_params = BillingFlowParams.newBuilder() \
            .setProductDetailsParamsList(product_params_list) \
            .build()
            
        result = self.client.launchBillingFlow(mActivity, flow_params)
        return result.getResponseCode() == BillingResponseCode.OK

    def _on_purchases_updated(self, billing_result, purchases):
        code = billing_result.getResponseCode()
        if code == BillingResponseCode.OK and purchases:
            for i in range(purchases.size()):
                purchase = purchases.get(i)
                self._handle_purchase(purchase)
        elif code == BillingResponseCode.USER_CANCELED:
            Logger.info("BillingService: User canceled the purchase.")
            if self.on_purchase_error:
                Clock.schedule_once(lambda dt: self.on_purchase_error("User canceled"))
        else:
            Logger.error(f"BillingService: Purchase failed with code {code}.")
            if self.on_purchase_error:
                Clock.schedule_once(lambda dt: self.on_purchase_error(f"Error code {code}"))

    def _handle_purchase(self, purchase):
        state = purchase.getPurchaseState()
        # 1 == PURCHASED
        if state == 1:
            if not purchase.isAcknowledged():
                params = AcknowledgePurchaseParams.newBuilder() \
                    .setPurchaseToken(purchase.getPurchaseToken()) \
                    .build()
                    
                def on_ack(result):
                    if result.getResponseCode() == BillingResponseCode.OK:
                        Logger.info("BillingService: Purchase acknowledged successfully.")
                        if self.on_purchase_success:
                            p_list = []
                            pids = purchase.getProducts()
                            if pids:
                                for i in range(pids.size()):
                                    p_list.append(pids.get(i))
                            Clock.schedule_once(lambda dt: self.on_purchase_success(p_list, purchase.getPurchaseToken()))
                            
                listener = AcknowledgePurchaseResponseListener(on_ack)
                self.client.acknowledgePurchase(params, listener)
            else:
                # Already acknowledged (e.g. recovering missed callbacks)
                if self.on_purchase_success:
                    p_list = []
                    pids = purchase.getProducts()
                    if pids:
                        for i in range(pids.size()):
                            p_list.append(pids.get(i))
                    Clock.schedule_once(lambda dt: self.on_purchase_success(p_list, purchase.getPurchaseToken()))

    def consume(self, purchase_token, callback=None):
        """
        Consume an in-app product so it can be bought again.
        """
        params = ConsumeParams.newBuilder().setPurchaseToken(purchase_token).build()
        
        def on_consume(result, token):
            success = result.getResponseCode() == BillingResponseCode.OK
            if callback:
                Clock.schedule_once(lambda dt: callback(success, token))
                
        listener = ConsumeResponseListener(on_consume)
        self.client.consumeAsync(params, listener)
