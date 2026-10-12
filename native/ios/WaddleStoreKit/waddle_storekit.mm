#include "waddle_storekit.h"

#include "core/config/engine.h"
#include "core/io/json.h"
#include "core/object/class_db.h"
#import "drivers/apple_embedded/app_delegate_service.h"
#import "drivers/apple_embedded/godot_view_controller.h"

#import <Foundation/Foundation.h>
#import "WaddleStoreKit-Swift.h"

static WaddleStoreKit *waddle_storekit = nullptr;

static NSString *to_ns(const String &value) {
    CharString utf8 = value.utf8();
    return [NSString stringWithUTF8String:utf8.get_data()];
}

void WaddleStoreKit::_bind_methods() {
    ClassDB::bind_method(D_METHOD("request_products", "product_ids"), &WaddleStoreKit::request_products);
    ClassDB::bind_method(D_METHOD("purchase", "product_id", "app_account_token"), &WaddleStoreKit::purchase);
    ClassDB::bind_method(D_METHOD("restore_purchases"), &WaddleStoreKit::restore_purchases);
    ClassDB::bind_method(D_METHOD("finish_transaction", "transaction_id"), &WaddleStoreKit::finish_transaction);
    ClassDB::bind_method(D_METHOD("begin_auth_session", "authorize_url", "request_id"), &WaddleStoreKit::begin_auth_session);
    ClassDB::bind_method(D_METHOD("end_auth_session", "request_id"), &WaddleStoreKit::end_auth_session);
    ClassDB::bind_method(D_METHOD("_receive_event", "event", "json"), &WaddleStoreKit::receive_event);
    ADD_SIGNAL(MethodInfo("products_received", PropertyInfo(Variant::ARRAY, "products")));
    ADD_SIGNAL(MethodInfo("purchase_received", PropertyInfo(Variant::DICTIONARY, "purchase")));
    ADD_SIGNAL(MethodInfo("purchase_failed", PropertyInfo(Variant::STRING, "message")));
    ADD_SIGNAL(MethodInfo("restore_finished"));
    ADD_SIGNAL(MethodInfo("auth_session_started", PropertyInfo(Variant::STRING, "request_id")));
    ADD_SIGNAL(MethodInfo("auth_session_finished", PropertyInfo(Variant::STRING, "request_id"), PropertyInfo(Variant::STRING, "outcome")));
    // Internal auth-client credential delivery; never forward into UI/logging.
    ADD_SIGNAL(MethodInfo("auth_session_authorized", PropertyInfo(Variant::STRING, "request_id"), PropertyInfo(Variant::STRING, "callback_code")));
}

void WaddleStoreKit::request_products(const PackedStringArray &p_ids) {
    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:p_ids.size()];
    for (int index = 0; index < p_ids.size(); ++index) {
        [ids addObject:to_ns(p_ids[index])];
    }
    [[WWStoreKitBridge shared] requestProducts:ids];
}

void WaddleStoreKit::purchase(const String &p_product_id, const String &p_account_token) {
    [[WWStoreKitBridge shared] purchaseProduct:to_ns(p_product_id) accountToken:to_ns(p_account_token)];
}

void WaddleStoreKit::restore_purchases() {
    [[WWStoreKitBridge shared] restorePurchases];
}

void WaddleStoreKit::finish_transaction(const String &p_transaction_id) {
    [[WWStoreKitBridge shared] finishTransaction:to_ns(p_transaction_id)];
}

void WaddleStoreKit::begin_auth_session(const String &p_authorize_url, const String &p_request_id) {
    NSString *url = to_ns(p_authorize_url);
    NSString *request_id = to_ns(p_request_id);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (waddle_storekit == nullptr) { return; }
        UIWindow *anchor = GDTAppDelegateService.viewController.view.window;
        [[WWAuthenticationBridge shared] beginAuthentication:url requestID:request_id anchor:anchor];
    });
}

void WaddleStoreKit::end_auth_session(const String &p_request_id) {
    NSString *request_id = to_ns(p_request_id);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[WWAuthenticationBridge shared] endAuthentication:request_id];
    });
}

void WaddleStoreKit::receive_event(const String &p_event, const String &p_json) {
    Variant value = JSON::parse_string(p_json);
    if (p_event == "restore_finished") {
        emit_signal(p_event);
    } else if ((p_event == "auth_session_started" || p_event == "auth_session_finished" || p_event == "auth_session_authorized") && value.get_type() == Variant::DICTIONARY) {
        Dictionary payload = value;
        if (payload.get("request_id", Variant()).get_type() != Variant::STRING) { return; }
        if (p_event == "auth_session_started") {
            emit_signal(p_event, payload["request_id"]);
        } else if (p_event == "auth_session_authorized" && payload.get("callback_code", Variant()).get_type() == Variant::STRING) {
            emit_signal(p_event, payload["request_id"], payload["callback_code"]);
        } else if (p_event == "auth_session_finished" && payload.get("outcome", Variant()).get_type() == Variant::STRING) {
            emit_signal(p_event, payload["request_id"], payload["outcome"]);
        }
    } else if ((p_event == "products_received" && value.get_type() == Variant::ARRAY) ||
               (p_event == "purchase_received" && value.get_type() == Variant::DICTIONARY) ||
               (p_event == "purchase_failed" && value.get_type() == Variant::STRING)) {
        emit_signal(p_event, value);
    }
}

void init_waddle_storekit() {
    ClassDB::register_class<WaddleStoreKit>();
    waddle_storekit = memnew(WaddleStoreKit);
    Engine::get_singleton()->add_singleton(Engine::Singleton("WaddleStoreKit", waddle_storekit));
    [WWStoreKitBridge shared].eventHandler = ^(NSString *event, NSString *json) {
        // Native shutdown clears this block before freeing the singleton. Swift
        // serializes callbacks on MainActor, then Godot delivers on its loop.
        if (waddle_storekit != nullptr) {
            waddle_storekit->call_deferred("_receive_event", String::utf8(event.UTF8String), String::utf8(json.UTF8String));
        }
    };
    dispatch_async(dispatch_get_main_queue(), ^{
        [WWAuthenticationBridge shared].eventHandler = ^(NSString *event, NSString *json) {
            if (waddle_storekit != nullptr) {
                waddle_storekit->call_deferred("_receive_event", String::utf8(event.UTF8String), String::utf8(json.UTF8String));
            }
        };
    });
}

void deinit_waddle_storekit() {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[WWAuthenticationBridge shared] stop];
    });
    [[WWStoreKitBridge shared] stop];
    Engine::get_singleton()->remove_singleton("WaddleStoreKit");
    if (waddle_storekit != nullptr) {
        memdelete(waddle_storekit);
        waddle_storekit = nullptr;
    }
}
