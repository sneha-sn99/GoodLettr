import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import getInvoiceContext from '@salesforce/apex/GoodLettrInvoiceService.getInvoiceContext';
import sendInvoice from '@salesforce/apex/GoodLettrInvoiceService.sendInvoice';

export default class GoodlettrSendInvoice extends LightningElement {
    _recordId;
    ctx = {};
    isLoading = true;
    isSending = false;
    loadError;
    cc = '';
    subject = '';
    body = '';

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value && value !== this._recordId) {
            this._recordId = value;
            this.load();
        }
    }

    async load() {
        this.isLoading = true;
        try {
            this.ctx = await getInvoiceContext({ orderId: this._recordId });
            this.subject = this.ctx.defaultSubject;
            this.body = this.ctx.defaultBody;
        } catch (error) {
            this.loadError = error?.body?.message || error?.message || 'Could not load the invoice details.';
        } finally {
            this.isLoading = false;
        }
    }

    get blockedReason() {
        return this.ctx?.canSend ? null : this.ctx?.blockedReason;
    }
    get billTo() {
        return this.ctx.billToName ? `${this.ctx.billToName} <${this.ctx.billToEmail || 'no email'}>` : 'Not set';
    }
    get pdfUrl() {
        return `/apex/GoodLettrInvoice?id=${this._recordId}`;
    }
    get sendDisabled() {
        return this.isLoading || this.isSending || !this.ctx?.canSend || !this.subject;
    }

    handleCc(e) {
        this.cc = e.detail.value;
    }
    handleSubject(e) {
        this.subject = e.detail.value;
    }
    handleBody(e) {
        this.body = e.detail.value;
    }
    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSend() {
        const ccAddresses = (this.cc || '').split(/[,;]/).map((s) => s.trim()).filter(Boolean);
        this.isSending = true;
        try {
            await sendInvoice({ orderId: this._recordId, ccAddresses, subject: this.subject, body: this.body });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Invoice sent',
                    message: `Invoice ${this.ctx.invoiceNumber} was emailed and the Order is now Billed.`,
                    variant: 'success'
                })
            );
            this.dispatchEvent(new RefreshEvent());
            this.handleClose();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Invoice not sent',
                    message: error?.body?.message || error?.message || 'Unknown error',
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isSending = false;
        }
    }
}