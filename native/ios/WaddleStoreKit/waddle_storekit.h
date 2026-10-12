#pragma once

#include "core/object/object.h"
#include "core/variant/variant.h"

class WaddleStoreKit : public Object {
    GDCLASS(WaddleStoreKit, Object);

protected:
    static void _bind_methods();

public:
    void request_products(const PackedStringArray &p_ids);
    void purchase(const String &p_product_id, const String &p_account_token);
    void restore_purchases();
    void finish_transaction(const String &p_transaction_id);
    void begin_auth_session(const String &p_authorize_url, const String &p_request_id);
    void end_auth_session(const String &p_request_id);
    void receive_event(const String &p_event, const String &p_json);
};

// Godot 4.7.1 generates plain C++ extern declarations in its Xcode project.
void init_waddle_storekit();
void deinit_waddle_storekit();
