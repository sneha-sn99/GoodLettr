import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import getHeadOffice from '@salesforce/apex/GoodLettrBranchService.getHeadOffice';
import checkBranches from '@salesforce/apex/GoodLettrBranchService.checkBranches';
import createBranches from '@salesforce/apex/GoodLettrBranchService.createBranches';

const EMPTY = () => ({
    name: '', phone: '', contactFirstName: '', contactLastName: '', contactEmail: '',
    street: '', city: '', postcode: '', country: 'United Kingdom'
});

/**
 * Add Branches: one branch form at a time. "Add more branches" keeps the branch in a list (held as JSON in the
 * browser) and clears the form; "Finish" sends the JSON to Apex, which creates every branch account and its
 * contact in one transaction. Nothing is saved before Finish.
 */
export default class GoodlettrAddBranches extends LightningElement {
    _recordId;
    headOffice;
    isLoading = true;
    isSaving = false;
    branches = [];      // list of branch objects; sent to Apex as JSON on Finish
    editIndex = null;   // index of the branch being edited, if any
    form = EMPTY();

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
        try {
            this.headOffice = await getHeadOffice({ accountId: this._recordId });
        } catch (error) {
            this.toast('Could not open Add Branches', this.message(error), 'error');
            this.close();
        } finally {
            this.isLoading = false;
        }
    }

    get header() {
        return this.headOffice ? `Add Branches to ${this.headOffice.name}` : 'Add Branches';
    }
    get notHeadOffice() {
        return this.headOffice && !this.headOffice.isHeadOffice;
    }
    get canEdit() {
        return !this.isLoading && this.headOffice && this.headOffice.isHeadOffice;
    }
    get hasBranches() {
        return this.branches.length > 0;
    }
    get formTitle() {
        return this.editIndex !== null ? `Edit branch ${this.editIndex + 1}` : `Branch ${this.branches.length + 1}`;
    }
    get addLabel() {
        return this.editIndex !== null ? 'Save branch & add more' : 'Add more branches';
    }
    get namePlaceholder() {
        return this.headOffice ? `e.g. ${this.headOffice.name} - Leeds` : '';
    }
    get branchRows() {
        return this.branches.map((b, index) => ({
            ...b,
            index,
            key: `${index}-${b.name}`,
            contact: [b.contactFirstName, b.contactLastName].filter(Boolean).join(' '),
            address: [b.street, b.city, b.postcode, b.country].filter(Boolean).join(', ')
        }));
    }
    get formIsEmpty() {
        const f = this.form;
        return ['name', 'phone', 'contactFirstName', 'contactLastName', 'contactEmail', 'street', 'city', 'postcode']
            .every((k) => !(f[k] || '').trim());
    }

    handleChange(event) {
        this.form = { ...this.form, [event.target.name]: event.target.value };
    }

    validateForm() {
        const inputs = [...this.template.querySelectorAll('lightning-input')];
        return inputs.reduce((ok, input) => input.reportValidity() && ok, true);
    }

    /** Keeps the current form in the list (new or edited) and clears it. */
    commitForm() {
        const branch = Object.fromEntries(Object.entries(this.form).map(([k, v]) => [k, (v || '').trim()]));
        if (this.editIndex !== null) {
            this.branches = this.branches.map((b, i) => (i === this.editIndex ? branch : b));
        } else {
            this.branches = [...this.branches, branch];
        }
        this.editIndex = null;
        this.form = EMPTY();
    }

    handleAddMore() {
        if (!this.validateForm()) return;
        const name = this.form.name;
        this.commitForm();
        this.toast('Branch added to the list', `${name} will be created when you click Finish.`, 'info');
    }

    handleEdit(event) {
        const index = Number(event.currentTarget.dataset.index);
        if (!this.formIsEmpty && this.editIndex === null) {
            if (!this.validateForm()) return;
            this.commitForm();
        }
        this.editIndex = index;
        this.form = { ...this.branches[index] };
    }

    handleRemove(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.branches = this.branches.filter((_, i) => i !== index);
        if (this.editIndex === index) {
            this.editIndex = null;
            this.form = EMPTY();
        }
    }

    async handleFinish() {
        // Include the branch on the form if the rep filled it in but didn't click "Add more branches"
        if (!this.formIsEmpty || this.editIndex !== null) {
            if (!this.validateForm()) return;
            this.commitForm();
        }
        if (!this.branches.length) {
            this.validateForm();
            this.toast('Nothing to add', 'Enter at least one branch.', 'warning');
            return;
        }
        const branchesJson = JSON.stringify(this.branches);
        this.isSaving = true;
        try {
            const check = await checkBranches({ parentId: this._recordId, branchesJson });
            if (check.hasErrors) {
                this.toast('Please fix these details', check.errors.join(' '), 'error', 'sticky');
                return;
            }
            if (check.warnings.length) {
                const proceed = await LightningConfirm.open({
                    label: 'Possible duplicates',
                    message: `${check.warnings.join(' ')} Do you want to create the branches anyway?`,
                    theme: 'warning',
                    variant: 'header'
                });
                if (!proceed) return;
            }
            const message = await createBranches({ parentId: this._recordId, branchesJson });
            this.toast('Branches created', message, 'success');
            this.dispatchEvent(new RefreshEvent());
            this.close();
        } catch (error) {
            this.toast('Branches not created', this.message(error), 'error', 'sticky');
        } finally {
            this.isSaving = false;
        }
    }

    async handleCancel() {
        if (this.branches.length) {
            const discard = await LightningConfirm.open({
                label: 'Discard branches?',
                message: `${this.branches.length} branch(es) in the list have not been saved. Close without creating them?`,
                theme: 'warning',
                variant: 'header'
            });
            if (!discard) return;
        }
        this.close();
    }

    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
    message(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }
    toast(title, message, variant, mode) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode: mode || 'dismissable' }));
    }
}