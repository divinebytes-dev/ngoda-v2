import { ethers } from "ethers";

import { AppError } from "./app-error.ts";

export interface TransactionData {
    v: string;
    r: string;
    s: string;

    a: number;
    f: number;
    g: number;

    c: string;

    t: number;
    e: number;

    ms: string;
}

export interface SenderApproval {
    v: string;
    r: string;
    b: string;
    a: string | number;
    c: string;
    bs: string;
}

export interface MerchantUser {
    role: string;
    walletAddress: string;
}

export class TransactionVerificationService {
    /*
     * Decode a Flutter Base64 signature without using Node Buffer.
     */
    private static signatureFromBase64(
        signature: string,
    ): string {
        const binary = atob(signature.trim());

        const bytes = Uint8Array.from(
            binary,
            (character) => character.charCodeAt(0),
        );

        return ethers.hexlify(bytes);
    }

    /*
     * Verify an EIP-191 signed message.
     *
     * ethers.verifyMessage() performs the same operation as:
     *
     * hashMessage(canonical)
     * recoverAddress(hash, signature)
     */
    private static verifyCanonicalSignature(
        canonical: string,
        base64Signature: string,
        expectedAddress: string,
    ): boolean {
        try {
            
            if (!base64Signature || !expectedAddress) {
                console.error(
                    "SIGNATURE_VERIFICATION_MISSING_DATA",
                    {
                    hasSignature: !!base64Signature,
                    expectedAddress,
                    canonical,
                    },
                );                
                return false;
            }

            const signature = this.signatureFromBase64(
                base64Signature,
            );

            const recoveredAddress = ethers.verifyMessage(
                canonical,
                signature,
            );

            return (
                recoveredAddress.toLowerCase() ===
                expectedAddress.toLowerCase()
            );
        } catch {
            return false;
        }
    }

    /*
     * Merchant-payment serialization.
     *
     * Do not change the order because it must exactly match Flutter.
     */
    static canonicalizePayment(
        payment: TransactionData,
    ): string {
        return [
            payment.v,
            payment.r,
            payment.s,
            payment.a.toString(),
            payment.f.toString(),
            payment.c,
            payment.t.toString(),
            payment.e.toString(),
        ].join("|");
    }

    /*
     * Normal transaction serialization.
     *
     * Do not change the order because it must exactly match Flutter.
     */
    static canonicalizeTransaction(
        transaction: TransactionData,
    ): string {
        return [
            transaction.v,
            transaction.r,
            transaction.s,
            transaction.a.toString(),
            transaction.f.toString(),
            transaction.g.toString(),
            transaction.c,
            transaction.t.toString(),
            transaction.e.toString(),
        ].join("|");
    }

    static canonicalizeApproval(
        approval: SenderApproval,
    ): string {
        return [
            approval.v,
            approval.r,
            approval.b,
            approval.a,
            approval.c,
        ].join("|");
    }

    static verifyMerchantSignature(
        payment: TransactionData,
        expectedAddress: string,
    ): boolean {
        return this.verifyCanonicalSignature(
            this.canonicalizePayment(payment),
            payment.ms,
            expectedAddress,
        );
    }

    static verifyTransactionSignature(
        transaction: TransactionData,
        expectedAddress: string,
    ): boolean {
        return this.verifyCanonicalSignature(
            this.canonicalizeTransaction(transaction),
            transaction.ms,
            expectedAddress,
        );
    }

    static verifySenderSignature(
        approval: SenderApproval,
        expectedAddress: string,
    ): boolean {
        return this.verifyCanonicalSignature(
            this.canonicalizeApproval(approval),
            approval.bs,
            expectedAddress,
        );
    }

    static validateFields(
        payment: TransactionData,
    ): void {
        if (!payment.r) {
            throw new AppError("REFERENCE_MISSING");
        }

        if (!payment.s) {
            throw new AppError("SIGNER_ID_MISSING");
        }

        if (!payment.c) {
            throw new AppError("CURRENCY_MISSING");
        }

        if (payment.a <= 0) {
            throw new AppError("INVALID_AMOUNT");
        }

        if (payment.f < 0) {
            throw new AppError("INVALID_FEE");
        }

        if (payment.g < 0) {
            throw new AppError("INVALID_TAX");
        }

        if (!payment.ms) {
            throw new AppError("SIGNER_SIGNATURE_MISSING");
        }
    }

    static validateTransactionFields(
        transaction: TransactionData,
    ): void {
        if (!transaction.r) {
            throw new AppError("REFERENCE_MISSING");
        }

        if (!transaction.s) {
            throw new AppError("SIGNER_ID_MISSING");
        }

        if (!transaction.c) {
            throw new AppError("CURRENCY_MISSING");
        }

        if (transaction.a <= 0) {
            throw new AppError("INVALID_AMOUNT");
        }

        if (transaction.f < 0) {
            throw new AppError("INVALID_FEE");
        }

        if (transaction.g < 0) {
            throw new AppError("INVALID_TAX");
        }

        if (!transaction.ms) {
            throw new AppError("SIGNER_SIGNATURE_MISSING");
        }
    }

    static validateTimestamp(
        payment: TransactionData,
    ): void {
        const now = Math.floor(Date.now() / 1000);

        if (payment.t > now + 300) {
            throw new AppError("INVALID_TIMESTAMP");
        }

        if (payment.e < now) {
            throw new AppError("REQUEST_EXPIRED");
        }

        if (payment.e <= payment.t) {
            throw new AppError("INVALID_EXPIRY");
        }

        const maxLifetimeSeconds = 60;

        if (payment.e - payment.t > maxLifetimeSeconds) {
            throw new AppError("EXPIRY_TOO_LONG");
        }
    }

    static validateTransactionTimestamp(
        transaction: TransactionData,
        vTime: number,
    ): void {
        const now = Math.floor(Date.now() / 1000);

        if (transaction.t > now + vTime) {
            throw new AppError("INVALID_TIMESTAMP");
        }

        if (transaction.e < now) {
            throw new AppError("REQUEST_EXPIRED");
        }

        if (transaction.e <= transaction.t) {
            throw new AppError("INVALID_EXPIRY");
        }

        const maxLifetimeSeconds = 600;

        if (
            transaction.e - transaction.t >
            maxLifetimeSeconds
        ) {
            throw new AppError("EXPIRY_TOO_LONG");
        }
    }

    static validateMerchantRole(
        merchant: MerchantUser,
    ): void {
        if (!merchant) {
            throw new AppError("MERCHANT_NOT_FOUND");
        }

        if (merchant.role !== "merchant") {
            throw new AppError("UNAUTHORISED");
        }
    }

    static recoverMerchantAddress(
        payment: TransactionData,
    ): string {
        const canonical = this.canonicalizePayment(
            payment,
        );

        const signature = this.signatureFromBase64(
            payment.ms,
        );

        return ethers.verifyMessage(
            canonical,
            signature,
        );
    }

    static async verifyPayment({
        payment,
        merchant,
    }: {
        payment: TransactionData;
        merchant: MerchantUser;
    }): Promise<void> {
        this.validateFields(payment);
        this.validateTimestamp(payment);
        this.validateMerchantRole(merchant);

        const valid = this.verifyMerchantSignature(
            payment,
            merchant.walletAddress,
        );

        if (!valid) {
            throw new AppError(
                "INVALID_MERCHANT_SIGNATURE",
            );
        }
    }
}