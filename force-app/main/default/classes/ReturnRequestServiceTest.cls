@IsTest
private class ReturnRequestServiceTest {

    @TestSetup
    static void setupData() {
        // No org data required; objects created in tests
    }

    // Helper to build DTO with one item
    private static ReturnRequestService.ReturnRequestDTO buildDTO(String orderNumber) {
        ReturnRequestService.ReturnItemDTO item = new ReturnRequestService.ReturnItemDTO();
        item.sku = 'SKU-001';
        item.productName = 'Blue T-Shirt';
        item.quantity = 2;
        item.unitPrice = 25.50;
        item.condition = 'Unopened';

        ReturnRequestService.ReturnRequestDTO dto = new ReturnRequestService.ReturnRequestDTO();
        dto.customerName = 'John Doe';
        dto.customerEmail = 'john@example.com';
        dto.orderNumber = orderNumber;
        dto.reason = 'Wrong Size';
        dto.items = new List<ReturnRequestService.ReturnItemDTO>{ item };
        return dto;
    }

    // Helper to build DTO with multiple items
    private static ReturnRequestService.ReturnRequestDTO buildDTOWithMultipleItems(String orderNumber) {
        ReturnRequestService.ReturnItemDTO item1 = new ReturnRequestService.ReturnItemDTO();
        item1.sku = 'SKU-001';
        item1.productName = 'Blue T-Shirt';
        item1.quantity = 2;
        item1.unitPrice = 25.50;
        item1.condition = 'Unopened';

        ReturnRequestService.ReturnItemDTO item2 = new ReturnRequestService.ReturnItemDTO();
        item2.sku = 'SKU-002';
        item2.productName = 'Red Hat';
        item2.quantity = 1;
        item2.unitPrice = 15.00;
        item2.condition = 'Opened';

        ReturnRequestService.ReturnRequestDTO dto = new ReturnRequestService.ReturnRequestDTO();
        dto.customerName = 'Jane Smith';
        dto.customerEmail = 'jane@example.com';
        dto.orderNumber = orderNumber;
        dto.reason = 'Damaged';
        dto.items = new List<ReturnRequestService.ReturnItemDTO>{ item1, item2 };
        return dto;
    }

    @IsTest
    static void testCreateReturnRequest_success() {
        ReturnRequestService.ReturnRequestDTO dto = buildDTO('ORD-1001');

        Test.startTest();
        Id rrId = ReturnRequestService.createReturnRequest(dto);
        Test.stopTest();

        System.assertNotEquals(null, rrId, 'Return Request Id should be returned');

        Return_Request__c rr = [
            SELECT Id, Status__c, Requested_At__c, Order_Number__c
            FROM Return_Request__c
            WHERE Id = :rrId
        ];
        System.assertEquals('New', rr.Status__c, 'Status should be New on create');
        System.assertNotEquals(null, rr.Requested_At__c, 'Requested_At__c should be set');
        System.assertEquals('ORD-1001', rr.Order_Number__c, 'Order number set');

        // Verify child item created and rollups reflect values after DML commit
        List<Return_Item__c> items = [
            SELECT Id, Quantity__c, Unit_Price__c, Refund_Amount__c
            FROM Return_Item__c
            WHERE Return_Request__c = :rrId
        ];
        System.assertEquals(1, items.size(), 'One return item should be created');
        System.assertEquals(2, items[0].Quantity__c, 'Quantity set');
        System.assertEquals(25.50, items[0].Unit_Price__c, 'Unit Price set');
        System.assertEquals(51.00, items[0].Refund_Amount__c, 'Refund Amount formula should compute');
    }

    @IsTest
    static void testCreateReturnRequest_success_multipleItems() {
        ReturnRequestService.ReturnRequestDTO dto = buildDTOWithMultipleItems('ORD-1002');

        Test.startTest();
        Id rrId = ReturnRequestService.createReturnRequest(dto);
        Test.stopTest();

        System.assertNotEquals(null, rrId, 'Return Request Id should be returned');

        Return_Request__c rr = [
            SELECT Id, Status__c, Requested_At__c, Order_Number__c
            FROM Return_Request__c
            WHERE Id = :rrId
        ];
        System.assertEquals('New', rr.Status__c, 'Status should be New on create');
        System.assertNotEquals(null, rr.Requested_At__c, 'Requested_At__c should be set');
        System.assertEquals('ORD-1002', rr.Order_Number__c, 'Order number set');

        // Verify child items created
        List<Return_Item__c> items = [
            SELECT Id, Quantity__c, Unit_Price__c, Refund_Amount__c
            FROM Return_Item__c
            WHERE Return_Request__c = :rrId
        ];
        System.assertEquals(2, items.size(), 'Two return items should be created');
    }

    @IsTest
    static void testCreateReturnRequest_duplicateOrderRejected() {
        // First create
        Id first = ReturnRequestService.createReturnRequest(buildDTO('ORD-1003'));
        System.assertNotEquals(null, first);

        // Duplicate create should throw
        Boolean thrown = false;
        try {
            ReturnRequestService.createReturnRequest(buildDTO('ORD-1003'));
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Duplicate Order Number'), 'Expect duplicate order message');
        }
        System.assertEquals(true, thrown, 'Should have thrown for duplicate order');
    }

    @IsTest
    static void testCreateReturnRequest_requiresAtLeastOneItem() {
        ReturnRequestService.ReturnRequestDTO dto = buildDTO('ORD-1004');
        dto.items = new List<ReturnRequestService.ReturnItemDTO>(); // empty

        Boolean thrown = false;
        try {
            ReturnRequestService.createReturnRequest(dto);
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('At least one return item'), 'Expect at least one item message');
        }
        System.assertEquals(true, thrown, 'Should have thrown for missing items');
    }

    @IsTest
    static void testCreateReturnRequest_requiresAtLeastOneValidItem() {
        ReturnRequestService.ReturnRequestDTO dto = buildDTO('ORD-1005');
        // Add a null item to the list - this should still allow creation since we have a valid item
        dto.items.add(null);
        
        // This should succeed because we still have one valid item
        Test.startTest();
        Id rrId = ReturnRequestService.createReturnRequest(dto);
        Test.stopTest();
        
        System.assertNotEquals(null, rrId, 'Should succeed when we have at least one valid item even with nulls in the list');
    }

    @IsTest
    static void testCreateReturnRequest_nullDto() {
        Boolean thrown = false;
        try {
            ReturnRequestService.createReturnRequest(null);
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Payload required'), 'Expect payload required message');
        }
        System.assertEquals(true, thrown, 'Should have thrown for null DTO');
    }

    @IsTest
    static void testCreateReturnRequest_missingOrderNumber() {
        ReturnRequestService.ReturnRequestDTO dto = buildDTO('ORD-1006');
        dto.orderNumber = '';

        Boolean thrown = false;
        try {
            ReturnRequestService.createReturnRequest(dto);
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Order Number is required'), 'Expect order number required message');
        }
        System.assertEquals(true, thrown, 'Should have thrown for missing order number');
    }

    @IsTest
    static void testCreateReturnRequest_missingCustomerName() {
        ReturnRequestService.ReturnRequestDTO dto = buildDTO('ORD-1007');
        dto.customerName = '';

        Boolean thrown = false;
        try {
            ReturnRequestService.createReturnRequest(dto);
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Customer Name is required'), 'Expect customer name required message');
        }
        System.assertEquals(true, thrown, 'Should have thrown for missing customer name');
    }

    @IsTest
    static void testCreateReturnRequest_missingCustomerEmail() {
        ReturnRequestService.ReturnRequestDTO dto = buildDTO('ORD-1008');
        dto.customerEmail = '';

        Boolean thrown = false;
        try {
            ReturnRequestService.createReturnRequest(dto);
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Customer Email is required'), 'Expect customer email required message');
        }
        System.assertEquals(true, thrown, 'Should have thrown for missing customer email');
    }

    @IsTest
    static void testGetReturnRequests_listsRecords() {
        // Seed multiple
        for (Integer i = 0; i < 3; i++) {
            ReturnRequestService.ReturnRequestDTO dto = buildDTO('ORD-LIST-' + i);
            ReturnRequestService.createReturnRequest(dto);
        }

        Test.startTest();
        List<Return_Request__c> recs = ReturnRequestService.getReturnRequests(2);
        Test.stopTest();

        System.assertEquals(2, recs.size(), 'Should respect limit');
        System.assertNotEquals(null, recs[0].Id);
    }

    @IsTest
    static void testGetReturnRequests_defaultLimit() {
        // Seed multiple
        for (Integer i = 0; i < 3; i++) {
            ReturnRequestService.ReturnRequestDTO dto = buildDTO('ORD-LIMIT-' + i);
            ReturnRequestService.createReturnRequest(dto);
        }

        Test.startTest();
        List<Return_Request__c> recs = ReturnRequestService.getReturnRequests(null);
        Test.stopTest();

        System.assertEquals(3, recs.size(), 'Should use default limit of 3 when null passed');
    }

    @IsTest
    static void testUpdateStatus_setsRequestedAtOnApproved() {
        Id rrId = ReturnRequestService.createReturnRequest(buildDTO('ORD-2001'));
        Return_Request__c before = [
            SELECT Id, Requested_At__c FROM Return_Request__c WHERE Id = :rrId
        ];
        // Clear Requested_At__c to simulate missing value
        before.Requested_At__c = null;
        update before;

        Test.startTest();
        ReturnRequestService.updateStatus(rrId, 'Approved');
        Test.stopTest();

        Return_Request__c after = [
            SELECT Id, Status__c, Requested_At__c FROM Return_Request__c WHERE Id = :rrId
        ];
        System.assertEquals('Approved', after.Status__c, 'Status should update');
        System.assertNotEquals(null, after.Requested_At__c, 'Requested_At should be populated when Approved');
    }

    @IsTest
    static void testUpdateStatus_setsRequestedAtOnRejected() {
        Id rrId = ReturnRequestService.createReturnRequest(buildDTO('ORD-2002'));
        Return_Request__c before = [
            SELECT Id, Requested_At__c FROM Return_Request__c WHERE Id = :rrId
        ];
        // Clear Requested_At__c to simulate missing value
        before.Requested_At__c = null;
        update before;

        Test.startTest();
        ReturnRequestService.updateStatus(rrId, 'Rejected');
        Test.stopTest();

        Return_Request__c after = [
            SELECT Id, Status__c, Requested_At__c FROM Return_Request__c WHERE Id = :rrId
        ];
        System.assertEquals('Rejected', after.Status__c, 'Status should update');
        System.assertNotEquals(null, after.Requested_At__c, 'Requested_At should be populated when Rejected');
    }

    @IsTest
    static void testUpdateStatus_invalidId() {
        Boolean thrown = false;
        try {
            ReturnRequestService.updateStatus(null, 'Approved');
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Return Request Id is required'), 'Expect return request id required message');
        }
        System.assertEquals(true, thrown, 'Should have thrown for null return request id');
    }

    @IsTest
    static void testUpdateStatus_invalidStatus() {
        Id rrId = ReturnRequestService.createReturnRequest(buildDTO('ORD-2003'));

        Boolean thrown = false;
        try {
            ReturnRequestService.updateStatus(rrId, '');
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('New Status is required'), 'Expect new status required message');
        }
        System.assertEquals(true, thrown, 'Should have thrown for empty status');
    }
}
