import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import getContext from '@salesforce/apex/GoodLettrPrimaryContactService.getContext';
import makePrimary from '@salesforce/apex/GoodLettrPrimaryContactService.makePrimary';

/**
 * Headless quick action "Make Primary" on Contact.
 * Top-account contact: made primary straight away. Branch contact: confirm first, because the
 * primary contact is held at the top account (one primary per agency group); the contact is then moved to the top account.
 */
export default class GoodlettrMakePrimary extends LightningElement {
    @api recordId;
    isRunning = false;

    @api async invoke() {
        if (this.isRunning) return;
        this.isRunning = true;
        try {
            const ctx = await getContext({ contactId: this.recordId });
            if (ctx.isAlreadyPrimary) {
                this.toast('Already primary', `${ctx.contactName} is already the primary contact for ${ctx.topAccountName}.`, 'info');
                return;
            }
            if (ctx.isChildAccount) {
                const current = ctx.currentPrimaryName
                    ? `${ctx.currentPrimaryName}${ctx.currentPrimaryAccountName ? ` (${ctx.currentPrimaryAccountName})` : ''} is currently the primary contact for ${ctx.topAccountName}.`
                    : `${ctx.topAccountName} has no primary contact at the moment.`;
                const ok = await LightningConfirm.open({
                    label: 'Make primary for the top account?',
                    message:
                        `${current} Primary contacts are held at the top account, not at branch level. ` +
                        `Do you want to make ${ctx.contactName} the primary contact for ${ctx.topAccountName}? ` +
                        `${ctx.contactName} will be moved from ${ctx.accountName} to ${ctx.topAccountName}.`,
                    theme: 'warning',
                    variant: 'header'
                });
                if (!ok) return;
            }
            const previous = await makePrimary({ contactId: this.recordId });
            this.toast(
                'Primary contact updated',
                `${ctx.contactName} is now the primary contact for ${ctx.topAccountName}.` +
                    (ctx.isChildAccount ? ` They have been moved from ${ctx.accountName} to ${ctx.topAccountName}.` : '') +
                    (previous ? ` ${previous} is no longer primary.` : ''),
                'success'
            );
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }, { recordId: ctx.topAccountId }]);
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.toast('Could not make primary', error?.body?.message || error?.message || 'Unknown error', 'error');
        } finally {
            this.isRunning = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}