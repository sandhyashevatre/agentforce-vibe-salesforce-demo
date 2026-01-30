/**
 * @description Service layer for Return Request operations.
 * UI-agnostic, bulk-safe, and enforces business rules.
 * 
 * Design:
 * - with sharing to respect org sharing
 * - Return Early pattern
 * - DTO pattern for inputs
 * - Validations:
 *   1) Prevent duplicate Order_Number__c
 *   2) Must have at least one Return_Item__c
 */
public with sharing class ReturnRequestService {

    /**
     * DTO for creating a Return Request and its items.
     */
    public class ReturnItemDTO {
        @AuraEnabled public String sku;
        @AuraEnabled public String productName;
        @AuraEnabled public Integer quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public String condition; // Unopened, Opened, Damaged
    }

    public class ReturnRequestDTO {
        @AuraEnabled public String customerName;
        @AuraEnabled public String customerEmail;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public String reason; // Picklist value
        @AuraEnabled public List<ReturnItemDTO> items;
    }

    /**
     * Creates a Return_Request__c with child Return_Item__c records.
     * - Validates: unique Order_Number__c, at least one item
     * - Sets Status to New if missing
     * - Sets Requested_At__c to now
     */
    @AuraEnabled(cacheable=false)
    public static Id createReturnRequest(ReturnRequestDTO dto) {
        if (dto == null) {
            throw new AuraHandledException('Payload required.');
        }
        if (String.isBlank(dto.orderNumber)) {
            throw new AuraHandledException('Order Number is required.');
        }
        if (String.isBlank(dto.customerName)) {
            throw new AuraHandledException('Customer Name is required.');
        }
        if (String.isBlank(dto.customerEmail)) {
            throw new AuraHandledException('Customer Email is required.');
        }
        if (dto.items == null || dto.items.isEmpty()) {
            throw new AuraHandledException('At least one return item is required.');
        }

        // Check duplicate Order_Number__c
        Integer existing = [SELECT COUNT() FROM Return_Request__c WHERE Order_Number__c = :dto.orderNumber];
        if (existing > 0) {
            throw new AuraHandledException('Duplicate Order Number. A return request already exists for this order.');
        }

        // Create parent
        Return_Request__c rr = new Return_Request__c();
        rr.Customer_Name__c = dto.customerName;
        rr.Customer_Email__c = dto.customerEmail;
        rr.Order_Number__c = dto.orderNumber;
        rr.Reason__c = dto.reason;
        rr.Status__c = 'New';
        rr.Requested_At__c = System.now();

        // Insert parent
        Database.SaveResult parentSr = Database.insert(rr);
        if (!parentSr.isSuccess()) {
            // Return Early with first error
            Database.Error err = parentSr.getErrors()[0];
            throw new AuraHandledException('Failed to create Return Request: ' + err.getMessage());
        }
        Id rrId = parentSr.getId();

        // Prepare children
        List<Return_Item__c> itemsToInsert = new List<Return_Item__c>();
        for (ReturnItemDTO item : dto.items) {
            if (item == null) continue;
            Return_Item__c ri = new Return_Item__c();
            ri.Return_Request__c = rrId;
            ri.SKU__c = item.sku;
            ri.Product_Name__c = item.productName;
            ri.Quantity__c = item.quantity;
            ri.Unit_Price__c = item.unitPrice;
            ri.Condition__c = item.condition;
            itemsToInsert.add(ri);
        }
        if (itemsToInsert.isEmpty()) {
            throw new AuraHandledException('At least one valid return item is required.');
        }

        // Insert children
        Database.SaveResult[] itemSrs = Database.insert(itemsToInsert, false);
        for (Database.SaveResult sr : itemSrs) {
            if (!sr.isSuccess()) {
                Database.Error err = sr.getErrors()[0];
                throw new AuraHandledException('Failed to create Return Item: ' + err.getMessage());
            }
        }

        return rrId;
    }

    /**
     * Retrieves Return Requests ordered by CreatedDate desc.
     * Supports filtering by status and searching by customer name or order number.
     */
    @AuraEnabled(cacheable=true)
    public static List<Return_Request__c> getReturnRequestsFiltered(Integer limitSize, String statusFilter, String searchText) {
        Integer lz = limitSize == null || limitSize <= 0 ? 20 : limitSize;
        String whereClause = '';
        List<Object> params = new List<Object>();
        
        if (statusFilter != null && statusFilter != 'All') {
            whereClause += ' AND Status__c = :statusFilter';
        }
        if (searchText != null && searchText != '') {
            whereClause += ' AND (Customer_Name__c LIKE :(\'%\' + searchText + \'%\') OR Order_Number__c LIKE :(\'%\' + searchText + \'%\'))';
        }
        
        String soql = 'SELECT Id, Name, Customer_Name__c, Customer_Email__c, Order_Number__c, Reason__c, Status__c, Requested_At__c';
        if (whereClause != '') {
            soql += ' FROM Return_Request__c WHERE Id != null' + whereClause + ' ORDER BY CreatedDate DESC LIMIT :lz';
        } else {
            soql += ' FROM Return_Request__c WHERE Id != null ORDER BY CreatedDate DESC LIMIT :lz';
        }
        return Database.query(soql);
    }

    /**
     * Gets detailed Return Request with child items.
     */
    @AuraEnabled(cacheable=true)
    public static Return_Request__c getReturnRequestDetails(Id returnRequestId) {
        if (returnRequestId == null) {
            throw new AuraHandledException('Return Request Id is required.');
        }
        return [
            SELECT Id, Name, Customer_Name__c, Customer_Email__c, Order_Number__c, Reason__c, Status__c, Requested_At__c,
                   (SELECT Id, SKU__c, Product_Name__c, Quantity__c, Unit_Price__c, Refund_Amount__c, Condition__c FROM Return_Items__r)
            FROM Return_Request__c
            WHERE Id = :returnRequestId
            LIMIT 1
        ];
    }

    /**
     * Updates the Status__c of a Return_Request__c.
     * Also ensures Requested_At__c is set when moving to Approved/Rejected.
     */
    @AuraEnabled
    public static void updateStatus(Id returnRequestId, String newStatus) {
        if (returnRequestId == null) {
            throw new AuraHandledException('Return Request Id is required.');
        }
        if (String.isBlank(newStatus)) {
            throw new AuraHandledException('New Status is required.');
        }
        Return_Request__c rr = [
            SELECT Id, Status__c, Requested_At__c
            FROM Return_Request__c
            WHERE Id = :returnRequestId
            LIMIT 1
        ];

        rr.Status__c = newStatus;
        if (newStatus == 'Approved' || newStatus == 'Rejected') {
            if (rr.Requested_At__c == null) {
                rr.Requested_At__c = System.now();
            }
        }
        Database.SaveResult sr = Database.update(rr);
        if (!sr.isSuccess()) {
            Database.Error err = sr.getErrors()[0];
            throw new AuraHandledException('Failed to update status: ' + err.getMessage());
        }
    }

    /**
     * DTO for AI Triage Recommendation
     */
    public class TriageRecommendation {
        @AuraEnabled public String recommendation; // "Auto-Approve" | "Manual Review" | "Reject"
        @AuraEnabled public String suggestedStatus; // "Under Review" | "Approved" | "Rejected"
        @AuraEnabled public Integer riskScore;
        @AuraEnabled public List<String> keySignals;
        @AuraEnabled public String summary;
        @AuraEnabled public List<String> suggestedNextActions;
    }

    /**
     * Generates AI-style triage recommendation for a return request
     * TODO: Replace rule-based logic with Einstein/LLM integration in future
     */
    @AuraEnabled(cacheable=false)
    public static TriageRecommendation getTriageRecommendation(Id returnRequestId) {
        if (returnRequestId == null) {
            throw new AuraHandledException('Return Request Id is required.');
        }
        
        // Get return request and its items
        Return_Request__c rr = [
            SELECT Id, Customer_Email__c, Reason__c, Status__c, Requested_At__c,
                   (SELECT Id, SKU__c, Product_Name__c, Quantity__c, Unit_Price__c, Refund_Amount__c, Condition__c FROM Return_Items__r)
            FROM Return_Request__c
            WHERE Id = :returnRequestId
            LIMIT 1
        ];
        
        TriageRecommendation rec = new TriageRecommendation();
        rec.keySignals = new List<String>();
        rec.suggestedNextActions = new List<String>();
        
        // Calculate totals
        Decimal totalRefund = 0;
        Integer totalQuantity = 0;
        Boolean hasDamagedItems = false;
        Boolean hasDamagedReason = false;
        
        if (rr.Return_Items__r != null) {
            for (Return_Item__c item : rr.Return_Items__r) {
                // Ensure Decimal added to Decimal, Integer added to Integer
                totalRefund += (item.Refund_Amount__c != null ? (Decimal)item.Refund_Amount__c : 0);
                totalQuantity += (item.Quantity__c != null ? (Integer)item.Quantity__c : 0);
                if (item.Condition__c == 'Damaged') {
                    hasDamagedItems = true;
                }
            }
        }
        
        // Check if same customer has multiple returns in last 30 days
        Boolean hasRecentReturns = false;
        if (rr.Customer_Email__c != null) {
            Datetime thirtyDaysAgo = System.now().addDays(-30);
            Integer recentCount = [
                SELECT COUNT()
                FROM Return_Request__c
                WHERE Customer_Email__c = :rr.Customer_Email__c
                AND Id != :rr.Id
                AND Requested_At__c >= :thirtyDaysAgo
            ];
            hasRecentReturns = recentCount > 0;
        }
        
        // Risk assessment based on conditions
        Integer riskScore = 0;
        List<String> keySignals = new List<String>();
        List<String> suggestedNextActions = new List<String>();
        
        // High risk conditions
        if (hasDamagedItems && rr.Reason__c == 'Damaged') {
            riskScore += 30;
            keySignals.add('Damaged items with damaged reason');
        }
        if (totalRefund > 200) {
            riskScore += 25;
            keySignals.add('High refund amount: $' + totalRefund);
        }
        if (totalQuantity > 5) {
            riskScore += 15;
            keySignals.add('Large quantity: ' + totalQuantity + ' items');
        }
        if (hasRecentReturns) {
            riskScore += 20;
            keySignals.add('Customer has multiple recent returns');
        }
        
        // Low risk conditions (lower score)
        if ((rr.Reason__c == 'Wrong Size' || rr.Reason__c == 'Changed Mind') && !hasDamagedItems) {
            riskScore -= 10; // Reduce risk for common reasons with good condition
            keySignals.add('Common reason with undamaged items');
        }
        
        // Ensure risk score is between 0-100
        riskScore = Math.max(0, Math.min(100, riskScore));
        
        // Determine recommendation based on risk score and other factors
        if (riskScore >= 70) {
            rec.recommendation = 'Reject';
            rec.suggestedStatus = 'Rejected';
            suggestedNextActions.add('Review with supervisor for policy compliance');
        } else if (riskScore >= 40) {
            rec.recommendation = 'Manual Review';
            rec.suggestedStatus = 'Under Review';
            suggestedNextActions.add('Verify item condition and refund eligibility');
            suggestedNextActions.add('Check customer return history');
        } else if ((rr.Reason__c == 'Wrong Size' || rr.Reason__c == 'Changed Mind') && !hasDamagedItems) {
            // Low risk for common reasons with good condition
            rec.recommendation = 'Auto-Approve';
            rec.suggestedStatus = 'Approved';
            suggestedNextActions.add('Approve return request automatically');
            suggestedNextActions.add('Generate refund for customer');
        } else {
            rec.recommendation = 'Manual Review';
            rec.suggestedStatus = 'Under Review';
            suggestedNextActions.add('Investigate further before approval');
        }
        
        // Set summary based on risk level
        if (riskScore >= 70) {
            rec.summary = 'High-risk return requiring supervisor review. Multiple risk factors detected.';
        } else if (riskScore >= 40) {
            rec.summary = 'Medium-risk return requiring manual review. Several cautionary indicators present.';
        } else {
            rec.summary = 'Low-risk return. Recommended for automatic approval.';
        }
        
        rec.riskScore = riskScore;
        rec.keySignals = keySignals;
        rec.suggestedNextActions = suggestedNextActions;
        
        return rec;
    }
    
    /**
     * Retrieves Return Requests ordered by CreatedDate desc.
     * Supports filtering by status and searching by customer name or order number.
     * Backward compatibility: accepts single integer parameter for limit only
     */
    @AuraEnabled(cacheable=true)
    public static List<Return_Request__c> getReturnRequests(Integer limitSize) {
        return getReturnRequestsFiltered(limitSize, null, null);
    }
}
