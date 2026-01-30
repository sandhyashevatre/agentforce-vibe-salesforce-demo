import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createReturnRequest from '@salesforce/apex/ReturnRequestService.createReturnRequest';

export default class ReturnRequestIntake extends LightningElement {
    // Core form fields
    @track customerName = '';
    @track customerEmail = '';
    @track orderNumber = '';
    @track reason = '';

    // Dynamic items
    @track items = [];

    reasonOptions = [
        { label: 'Wrong Size', value: 'Wrong Size' },
        { label: 'Damaged', value: 'Damaged' },
        { label: 'Not as Described', value: 'Not as Described' },
        { label: 'Changed Mind', value: 'Changed Mind' },
        { label: 'Other', value: 'Other' }
    ];

    conditionOptions = [
        { label: 'Unopened', value: 'Unopened' },
        { label: 'Opened', value: 'Opened' },
        { label: 'Damaged', value: 'Damaged' }
    ];

    get isSubmitDisabled() {
        // Basic client-side validation
        if (!this.customerName || !this.customerEmail || !this.orderNumber) {
            return true;
        }
        if (!this.items || this.items.length === 0) {
            return true;
        }
        return false;
    }

    handleCustomerName = (e) => { this.customerName = e.detail.value; };
    handleCustomerEmail = (e) => { this.customerEmail = e.detail.value; };
    handleOrderNumber = (e) => { this.orderNumber = e.detail.value; };
    handleReason = (e) => { this.reason = e.detail.value; };

    handleAddItem = () => {
        const newItem = {
            id: Date.now().toString(),
            sku: '',
            productName: '',
            quantity: 1,
            unitPrice: 0,
            condition: 'Unopened'
        };
        this.items = [...this.items, newItem];
    };

    handleRemoveItem = (e) => {
        const id = e.currentTarget.dataset.id;
        this.items = this.items.filter(i => i.id !== id);
    };

    handleItemChange = (e) => {
        const id = e.currentTarget.dataset.id;
        const field = e.currentTarget.dataset.field;
        const value = e.detail.value;
        this.items = this.items.map(it => it.id === id ? { ...it, [field]: value } : it);
    };

    async handleSubmit() {
        try {
            const payload = {
                customerName: this.customerName,
                customerEmail: this.customerEmail,
                orderNumber: this.orderNumber,
                reason: this.reason,
                items: this.items.map(i => ({
                    sku: i.sku || null,
                    productName: i.productName || null,
                    quantity: i.quantity ? Number(i.quantity) : null,
                    unitPrice: i.unitPrice ? Number(i.unitPrice) : null,
                    condition: i.condition || null
                }))
            };

            const rrId = await createReturnRequest({ dto: payload });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Return Request created',
                    variant: 'success'
                })
            );

            // Navigate to record
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                // Use standard URL navigation for simplicity; lightning/navigation could also be used
                window.open('/lightning/r/Return_Request__c/' + rrId + '/view', '_self');
            }, 500);

        } catch (e) {
            const message = (e && e.body && e.body.message) ? e.body.message : (e && e.message) ? e.message : 'Unknown error';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error creating Return Request',
                    message,
                    variant: 'error'
                })
            );
        }
    }
}
