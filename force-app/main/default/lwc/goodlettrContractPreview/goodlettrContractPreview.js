import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import saveContractToFiles from '@salesforce/apex/GoodLettrContractService.saveContractToFiles';
import markContractGenerated from '@salesforce/apex/GoodLettrContractService.markContractGenerated';

export default class GoodlettrContractPreview extends LightningElement {
    _recordId;
    isSaving = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value && value !== this._recordId) {
            this._recordId = value;
            this.markGenerated();
        }
    }

    // Opening this action counts as generating the contract: stamp the Opportunity so the
    // stage flow moves it to Proposal/Price Quote, then refresh the record page.
    async markGenerated() {
        try {
            await markContractGenerated({ opportunityId: this._recordId });
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Stage not updated',
                    message: error?.body?.message || error?.message || 'Unknown error',
                    variant: 'warning'
                })
            );
        }
    }

    get pdfUrl() {
        return this.recordId ? `/apex/GoodLettrContract?id=${this.recordId}` : null;
    }

    handleOpen() {
        window.open(this.pdfUrl, '_blank');
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSave() {
        this.isSaving = true;
        try {
            await saveContractToFiles({ opportunityId: this.recordId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Contract saved',
                    message: "The contract PDF was added to this Opportunity's Files.",
                    variant: 'success'
                })
            );
            this.dispatchEvent(new RefreshEvent());
            this.handleClose();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not save the contract',
                    message: error?.body?.message || error?.message || 'Unknown error',
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }
}