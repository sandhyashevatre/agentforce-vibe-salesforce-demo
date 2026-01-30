import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getReturnRequests from '@salesforce/apex/ReturnRequestService.getReturnRequests';

export default class ReturnRequestList extends LightningElement {
    @track status = '';
    @track rows = [];

    statusOptions = [
        { label: 'All Statuses', value: '' },
        { label: 'New', value: 'New' },
        { label: 'Under Review', value: 'Under Review' },
        { label: 'Approved', value: 'Approved' },
        { label: 'Rejected', value: 'Rejected' },
        { label: 'Completed', value: 'Completed' }
    ];

    columns = [
        { label: 'Request #', fieldName: 'Name' },
        { label: 'Customer', fieldName: 'Customer_Name__c' },
        { label: 'Order #', fieldName: 'Order_Number__c' },
        { label: 'Status', fieldName: 'Status__c' },
        { label: 'Requested At', fieldName: 'Requested_At__c', type: 'date', typeAttributes: {
            year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit'
        }},
        { type: 'button', typeAttributes: { label: 'Open', name: 'open', variant: 'base' }, fixedWidth: 100 }
    ];

    connectedCallback() {
        this.refreshList();
    }

    async refreshList() {
        try {
            const result = await getReturnRequests({ limitSize: 20 });
            let data = result || [];
            if (this.status) {
                data = data.filter(r => r.Status__c === this.status);
            }
            this.rows = data;
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error loading Return Requests',
                message: (e && e.body && e.body.message) ? e.body.message : 'Unknown error',
                variant: 'error'
            }));
        }
    }

    handleStatusChange = (e) => {
        this.status = e.detail.value;
        this.refreshList();
    };

    handleRowAction = (e) => {
        const actionName = e.detail.action.name;
        const row = e.detail.row;
        if (actionName === 'open' && row && row.Id) {
            window.open('/lightning/r/Return_Request__c/' + row.Id + '/view', '_self');
        }
    };
}
