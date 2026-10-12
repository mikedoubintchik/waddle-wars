/* Read-only CMS verification. stdin: bounded DER SignedData containing data.
 * stdout: verified payload for the Python caller only; never print directly.
 * No certificate import, keychain writes, private-key operations, or network.
 * Apple's public policy factory recognizes provisioning policy OID .56:
 * https://github.com/apple-oss-distributions/Security/blob/main/OSX/sec/Security/SecPolicy.list
 * https://github.com/apple-oss-distributions/Security/blob/main/OSX/sec/Security/SecPolicy.c
 */
#include <CoreFoundation/CoreFoundation.h>
#include <Security/CMSDecoder.h>
#include <Security/SecPolicy.h>
#include <Security/SecTrust.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_BYTES (8 * 1024 * 1024)

/* Reject encrypted/nested CMS before CMSDecoder can attempt decryption.
 * This is only a conservative DER envelope guard, not a signature parser. */
static int der_item(const unsigned char **cursor, const unsigned char *end,
                    unsigned char tag, const unsigned char **body, size_t *length) {
    const unsigned char *p = *cursor;
    if (end - p < 2 || *p++ != tag) return 0;
    size_t n = *p++;
    if (n & 0x80) {
        size_t count = n & 0x7f;
        if (!count || count > 4 || (size_t)(end - p) < count || !*p) return 0;
        n = 0;
        for (size_t i = 0; i < count; ++i) n = (n << 8) | *p++;
        if (n < 128) return 0;
    }
    if (n > (size_t)(end - p)) return 0;
    *body = p; *length = n; *cursor = p + n;
    return 1;
}

static int plain_signed_data(const unsigned char *raw, size_t size) {
    const unsigned char signed_oid[] = {0x2a,0x86,0x48,0x86,0xf7,0x0d,1,7,2};
    const unsigned char data_oid[] = {0x2a,0x86,0x48,0x86,0xf7,0x0d,1,7,1};
    const unsigned char *p = raw, *end = raw + size, *body;
    size_t n;
    if (!der_item(&p,end,0x30,&body,&n) || p != end) return 0;
    p=body; end=body+n;
    if (!der_item(&p,end,0x06,&body,&n) || n != sizeof(signed_oid) || memcmp(body,signed_oid,n)) return 0;
    if (!der_item(&p,end,0xa0,&body,&n) || p != end) return 0;
    p=body; end=body+n;
    if (!der_item(&p,end,0x30,&body,&n) || p != end) return 0;
    p=body; end=body+n;
    if (!der_item(&p,end,0x02,&body,&n) || !der_item(&p,end,0x31,&body,&n)
        || !der_item(&p,end,0x30,&body,&n)) return 0;
    p=body; end=body+n;
    return der_item(&p,end,0x06,&body,&n) && n == sizeof(data_oid) && !memcmp(body,data_oid,n);
}

int main(void) {
    int result = 1;
    unsigned char *raw = malloc(MAX_BYTES + 1);
    CMSDecoderRef decoder = NULL;
    SecPolicyRef policy = NULL;
    SecTrustRef trust = NULL;
    CFDataRef content = NULL;
    CFDictionaryRef properties = NULL;
    CFErrorRef error = NULL;
    size_t count = 0;
    CMSSignerStatus signer = kCMSSignerUnsigned;
    if (!raw) goto done;
    size_t size = fread(raw, 1, MAX_BYTES + 1, stdin);
    if (ferror(stdin) || !size || size > MAX_BYTES || !plain_signed_data(raw,size)) goto done;
    if (CMSDecoderCreate(&decoder) != errSecSuccess
        || CMSDecoderUpdateMessage(decoder,raw,size) != errSecSuccess
        || CMSDecoderFinalizeMessage(decoder) != errSecSuccess
        || CMSDecoderGetNumSigners(decoder,&count) != errSecSuccess || count != 1) goto done;
    CFStringRef oid = CFSTR("1.2.840.113635.100.1.56");
    policy = SecPolicyCreateWithProperties(oid,NULL);
    if (!policy) goto done;
    properties = SecPolicyCopyProperties(policy);
    if (!properties || !CFDictionaryGetValue(properties,kSecPolicyOid)
        || CFGetTypeID(CFDictionaryGetValue(properties,kSecPolicyOid)) != CFStringGetTypeID()
        || !CFEqual(CFDictionaryGetValue(properties,kSecPolicyOid),oid)) goto done;
    /* False defers trust so network fetching can be prohibited before evaluation. */
    if (CMSDecoderCopySignerStatus(decoder,0,policy,false,&signer,&trust,NULL) != errSecSuccess
        || signer != kCMSSignerValid || !trust
        || SecTrustSetNetworkFetchAllowed(trust,false) != errSecSuccess
        || !SecTrustEvaluateWithError(trust,&error)
        || SecTrustGetCertificateCount(trust) != 3
        || CMSDecoderCopyContent(decoder,&content) != errSecSuccess || !content) goto done;
    CFIndex length = CFDataGetLength(content);
    if (length <= 0 || length > MAX_BYTES
        || fwrite(CFDataGetBytePtr(content),1,(size_t)length,stdout) != (size_t)length
        || fflush(stdout)) goto done;
    result = 0;
done:
    if (result) fputs("Apple profile CMS signature/trust verification rejected input\n",stderr);
    if (error) CFRelease(error);
    if (properties) CFRelease(properties);
    if (content) CFRelease(content);
    if (trust) CFRelease(trust);
    if (policy) CFRelease(policy);
    if (decoder) CFRelease(decoder);
    free(raw);
    return result;
}
