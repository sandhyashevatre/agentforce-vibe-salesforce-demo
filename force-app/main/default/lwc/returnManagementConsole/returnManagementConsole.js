import { LightningElement, track, api, wire } from 'lwc';
import createReturnRequest from '@salesforce/apex/ReturnRequestService.createReturnRequest';
import getReturnRequestsFiltered from '@salesforce/apex/ReturnRequestService.getReturnRequestsFiltered';
import getReturnRequestDetails from '@salesforce/apex/ReturnRequestService.getReturnRequestDetails';
import updateStatus from '@salesforce/apex/ReturnRequestService.updateStatus';
import getTriageRecommendation from '@salesforce/apex/ReturnRequestService.getTriageRecommendation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class ReturnManagementConsole extends LightningElement {
    // Create form data
    @track customerName = '';
    @track customerEmail = '';
    @track orderNumber = '';
    @track reason = '';
    @track items = [{ id: Date.now(), sku: '', productName: '', quantity: '', unitPrice: '', condition: '' }];
    
    // Filter and search
    @track statusFilter = 'All';
    @track searchText = '';
    
    // List data
    @track returnRequests = [];
    @track selectedReturnRequest = null;
    @track selectedReturnRequestDetails = null;
    
    // Safe initialization for return request ID
    selectedReturnRequestId = null;
    
    // Safe initialization for return request details
    @track returnRequestDetails = {};
    @track returnItems = [];
    
    // Getter to check if a return request is selected
    get hasSelectedReturn() {
        return !!this.selectedReturnRequestId;
    }
    
    // Status options
    @track statusOptions = [
        { label: 'All', value: 'All' },
        { label: 'New', value: 'New' },
        { label: 'Approved', value: 'Approved' },
        { label: 'Rejected', value: 'Rejected' }
    ];
    
    // Reason options for dropdown
    @track reasonOptions = [
        { label: 'Wrong Size', value: 'Wrong Size' },
        { label: 'Damaged', value: 'Damaged' },
        { label: 'Not as Described', value: 'Not as Described' },
        { label: 'Changed Mind', value: 'Changed Mind' },
        { label: 'Other', value: 'Other' }
    ];
    
    // Condition options for dropdown
    @track conditionOptions = [
        { label: 'Unopened', value: 'Unopened' },
        { label: 'Opened', value: 'Opened' },
        { label: 'Damaged', value: 'Damaged' }
    ];
    
    // Columns for return requests table
    @track columns = [
        { label: 'Name', fieldName: 'Name', type: 'text' },
        { label: 'Customer Name', fieldName: 'Customer_Name__c', type: 'text' },
        { label: 'Order Number', fieldName: 'Order_Number__c', type: 'text' },
        { label: 'Reason', fieldName: 'Reason__c', type: 'text' },
        { label: 'Status', fieldName: 'Status__c', type: 'text' },
        { label: 'Requested At', fieldName: 'Requested_At__c', type: 'date' }
    ];
    
    // Columns for return items table
    @track itemColumns = [
        { label: 'SKU', fieldName: 'SKU__c', type: 'text' },
        { label: 'Product Name', fieldName: 'Product_Name__c', type: 'text' },
        { label: 'Quantity', fieldName: 'Quantity__c', type: 'number' },
        { label: 'Unit Price', fieldName: 'Unit_Price__c', type: 'currency' },
        { label: 'Condition', fieldName: 'Condition__c', type: 'text' },
        { label: 'Refund Amount', fieldName: 'Refund_Amount__c', type: 'currency' }
    ];
    
    // Form validation
    @track isFormValid = true;
    
    // Loading states
    @track isLoading = false;
    
    // Get the picklist values for reason
    @wire(getReturnRequestsFiltered, { limitSize: 20, statusFilter: '$statusFilter', searchText: '$searchText' })
    wiredReturnRequests({ error, data }) {
        if (data) {
            this.returnRequests = data;
            // If we have a selected request, refresh its details
            if (this.selectedReturnRequest && this.selectedReturnRequest.Id) {
                this.loadReturnRequestDetails(this.selectedReturnRequest.Id);
            }
        } else if (error) {
            this.showToast('Error', 'Failed to load return requests', 'error');
        }
    }
    
    // Handle form input changes
    handleInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        
        if (field === 'customerName') {
            this.customerName = value;
        } else if (field === 'customerEmail') {
            this.customerEmail = value;
        } else if (field === 'orderNumber') {
            this.orderNumber = value;
        } else if (field === 'reason') {
            this.reason = value;
        }
    }
    
    // Handle item input changes
    handleItemChange(event) {
        const itemId = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = event.target.value;
        
        const itemIndex = this.items.findIndex(item => item.id === parseInt(itemId));
        if (itemIndex !== -1) {
            this.items[itemIndex][field] = value;
        }
    }
    
    // Add a new item row
    handleAddItem() {
        this.items = [...this.items, {
            id: Date.now(),
            sku: '',
            productName: '',
            quantity: '',
            unitPrice: '',
            condition: ''
        }];
    }
    
    // Remove an item row
    handleRemoveItem(event) {
        const itemId = event.target.dataset.id;
        if (this.items.length > 1) {
            this.items = this.items.filter(item => item.id !== parseInt(itemId));
        }
    }
    
    // Validate form
    validateForm() {
        let isValid = true;
        
        // Validate main form fields
        if (!this.customerName.trim()) {
            isValid = false;
        }
        if (!this.customerEmail.trim()) {
            isValid = false;
        }
        if (!this.orderNumber.trim()) {
            isValid = false;
        }
        if (!this.reason) {
            isValid = false;
        }
        
        // Validate items
        for (let i = 0; i < this.items.length; i++) {
            const item = this.items[i];
            if (!item.sku.trim() || !item.productName.trim() || 
                !item.quantity || !item.unitPrice || !item.condition) {
                isValid = false;
                break;
            }
        }
        
        this.isFormValid = isValid;
        return isValid;
    }
    
    // Submit the form
    async handleSubmit() {
        if (!this.validateForm()) {
            this.showToast('Error', 'Please fill in all required fields', 'error');
            return;
        }
        
        this.isLoading = true;
        
        try {
            // Prepare DTO
            const dto = {
                customerName: this.customerName,
                customerEmail: this.customerEmail,
                orderNumber: this.orderNumber,
                reason: this.reason,
                items: this.items.map(item => ({
                    sku: item.sku,
                    productName: item.productName,
                    quantity: parseInt(item.quantity),
                    unitPrice: parseFloat(item.unitPrice),
                    condition: item.condition
                }))
            };
            
            // Call Apex
            const returnRequestId = await createReturnRequest(dto);
            
            // Show success message
            this.showToast('Success', 'Return request created successfully', 'success');
            
            // Reset form
            this.resetForm();
            
            // Refresh the list
            await refreshApex(this.wiredReturnRequests);
            
            // Select the newly created request
            const newRequest = this.returnRequests.find(req => req.Id === returnRequestId);
            if (newRequest) {
                this.handleSelectRequest(newRequest);
            }
        } catch (error) {
            this.showToast('Error', error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // Reset the form
    resetForm() {
        this.customerName = '';
        this.customerEmail = '';
        this.orderNumber = '';
        this.reason = '';
        this.items = [{ id: Date.now(), sku: '', productName: '', quantity: '', unitPrice: '', condition: '' }];
    }
    
    // Handle status update
    async handleUpdateStatus(event) {
        const newStatus = event.target.value;
        const returnRequestId = this.selectedReturnRequest?.Id;
        
        if (!returnRequestId) {
            this.showToast('Error', 'No return request selected', 'error');
            return;
        }
        
        try {
            await updateStatus({ returnRequestId, newStatus });
            this.showToast('Success', 'Status updated successfully', 'success');
            
            // Refresh the list and details
            await refreshApex(this.wiredReturnRequests);
            if (this.selectedReturnRequest) {
                this.loadReturnRequestDetails(returnRequestId);
            }
        } catch (error) {
            this.showToast('Error', error.body.message, 'error');
        }
    }
    
    // Load return request details
    async loadReturnRequestDetails(returnRequestId) {
        try {
            const result = await getReturnRequestDetails({ returnRequestId });
            this.selectedReturnRequestDetails = result || {};
        } catch (error) {
            this.showToast('Error', 'Failed to load return request details', 'error');
            this.selectedReturnRequestDetails = {};
        }
    }
    
    // Handle row selection
    handleSelectRequest(request) {
        this.selectedReturnRequest = request;
        this.loadReturnRequestDetails(request.Id);
    }
    
    // Handle filter change
    handleFilterChange(event) {
        this.statusFilter = event.target.value;
    }
    
    // Handle search change
    handleSearchChange(event) {
        this.searchText = event.target.value;
    }
    
    // Toast notification
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
    
    // Calculate totals for selected request
    get totalItems() {
        return this.selectedReturnRequestDetails?.Return_Items__r?.length ?? 0;
    }
    
    get totalRefundAmount() {
        const items = this.selectedReturnRequestDetails?.Return_Items__r ?? [];
        return items.reduce((total, item) => {
            return total + (item?.Refund_Amount__c || 0);
        }, 0);
    }
    
    // Triage data
    @track triageRecommendation = null;
    @track isAnalyzing = false;
    
    // Get KPI data
    get newCount() {
        return this.returnRequests.filter(req => req.Status__c === 'New').length;
    }
    
    get underReviewCount() {
        return this.returnRequests.filter(req => req.Status__c === 'Under Review').length;
    }
    
    get approvedCount() {
        return this.returnRequests.filter(req => req.Status__c === 'Approved').length;
    }
    
    get rejectedCount() {
        return this.returnRequests.filter(req => req.Status__c === 'Rejected').length;
    }
    
    // Get total refund amount for all listed items
    get totalRefundForList() {
        let total = 0;
        for (const request of this.returnRequests) {
            if (request.Return_Items__r) {
                for (const item of request.Return_Items__r) {
                    total += (item.Refund_Amount__c || 0);
                }
            }
        }
        return total;
    }
    
    // Check if triage has key signals
    get hasKeySignals() {
        return this.triageRecommendation && 
               this.triageRecommendation.keySignals && 
               this.triageRecommendation.keySignals.length > 0;
    }
    
    // Check if triage has suggested actions
    get hasSuggestedActions() {
        return this.triageRecommendation && 
               this.triageRecommendation.suggestedNextActions && 
               this.triageRecommendation.suggestedNextActions.length > 0;
    }
    
    // Handle triage analysis
    async handleAnalyzeReturn() {
        if (!this.selectedReturnRequest?.Id) {
            this.showToast('Error', 'Please select a return request first', 'error');
            return;
        }
        
        this.isAnalyzing = true;
        this.triageRecommendation = null;
        
        try {
            const result = await getTriageRecommendation({ returnRequestId: this.selectedReturnRequest.Id });
            this.triageRecommendation = result;
        } catch (error) {
            this.showToast('Error', 'Failed to analyze return: ' + error.body.message, 'error');
        } finally {
            this.isAnalyzing = false;
        }
    }
    
    // Apply suggested status from triage
    handleApplySuggestedStatus() {
        if (this.triageRecommendation?.suggestedStatus) {
            this.handleUpdateStatus({ target: { value: this.triageRecommendation.suggestedStatus } });
        }
    }
}
