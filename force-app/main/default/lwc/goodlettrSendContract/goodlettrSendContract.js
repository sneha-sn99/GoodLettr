import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import getSendContext from '@salesforce/apex/GoodLettrContractService.getSendContext';
import sendContract from '@salesforce/apex/GoodLettrContractService.sendContract';

export default class GoodlettrSendContract extends LightningElement {
    _recordId;
    isLoading = true;
    isSending = false;
    loadError;
    recipients = [];
    hasLines = true;
    contactId;
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
            const ctx = await getSendContext({ opportunityId: this._recordId });
            this.recipients = ctx.recipients || [];
            this.hasLines = ctx.hasLines;
            this.subject = ctx.defaultSubject;
            this.body = ctx.defaultBody;
            this.contactId = this.recipients.length ? this.recipients[0].id : undefined;
        } catch (error) {
            this.loadError = error?.body?.message || error?.message || 'Could not load the email details.';
        } finally {
            this.isLoading = false;
        }
    }

    get recipientOptions() {
        return this.recipients.map((r) => ({ label: r.label, value: r.id }));
    }
    get noRecipients() {
        return !this.recipients.length;
    }
    get noLines() {
        return !this.hasLines;
    }
    get pdfUrl() {
        return `/apex/GoodLettrContract?id=${this._recordId}`;
    }
    get sendDisabled() {
        return this.isLoading || this.isSending || !this.contactId || !this.subject;
    }

    handleContact(e) {
        this.contactId = e.detail.value;
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
        const inputs = [...this.template.querySelectorAll('lightning-combobox, lightning-input')];
        if (!inputs.every((i) => i.reportValidity())) {
            return;
        }
        const ccAddresses = (this.cc || '')
            .split(/[,;]/)
            .map((s) => s.trim())
            .filter(Boolean);
        this.isSending = true;
        try {
            await sendContract({
                opportunityId: this._recordId,
                contactId: this.contactId,
                ccAddresses,
                subject: this.subject,
                body: this.body
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Contract sent',
                    message: "The contract was emailed and a copy saved to this Opportunity's Files.",
                    variant: 'success'
                })
            );
            this.dispatchEvent(new RefreshEvent());
            this.handleClose();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Contract not sent',
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