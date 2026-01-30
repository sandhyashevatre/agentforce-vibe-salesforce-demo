# AI Agent Instructions for demosfvibe

A Salesforce DX project for return request automation with LWC components and Apex service layer.

## Architecture

**Three-tier structure:**
1. **Apex Service Layer** ([ReturnRequestService.cls](../force-app/main/default/classes/ReturnRequestService.cls)): UI-agnostic business logic with DTO pattern for inputs
2. **LWC Components**: Consumption layer (intake form, request list, management console)
3. **Custom Objects**: `Return_Request__c` (parent) ↔ `Return_Item__c` (child items with 1:N relationship)

**Key Design Pattern:** with sharing + Return Early pattern. Service methods use `@AuraEnabled` for LWC invocation.

## Core Domain Logic

### Return Request Lifecycle
- **Status States**: New → Under Review → Approved/Rejected → Completed
- **Critical Validations** (in service layer):
  - Unique `Order_Number__c` per request (prevent duplicates)
  - At least one `Return_Item__c` required (no orphan requests)
  - All required fields: `Customer_Name__c`, `Customer_Email__c`, `Order_Number__c`

### Triage Recommendation System
`getTriageRecommendation()` implements rule-based AI logic (future: Einstein/LLM integration):
- **Risk Score** (0-100): Combines signals (damaged items +30, high refund >$200 +25, quantity >5 +15, recent returns +20)
- **Three Recommendation Types**: Auto-Approve (low-risk standard returns), Manual Review (medium-risk), Reject (high-risk)
- **Key Signals**: Damaged condition, refund amount, quantity, customer return history

## Developer Workflows

### Build & Deploy
```bash
npm run lint              # Validate Apex/LWC code
npm test or npm run test:unit  # Run LWC Jest tests
npm run test:unit:watch  # Watch mode for development
npm run test:unit:coverage    # Coverage report
npm run prettier         # Auto-format all files
```

### Salesforce CLI (implicit in deployment)
- Scratch org configured in `sfdx-project.json` with API v65.0
- Force-app package is default deployment source

### Testing
- **Jest configuration** in `jest.config.js` (standard `@salesforce/sfdx-lwc-jest`)
- **Test class**: [ReturnRequestServiceTest.cls](../force-app/main/default/classes/ReturnRequestServiceTest.cls) covers create, read, update, triage scenarios
- **Husky + lint-staged**: Pre-commit hooks run prettier + eslint on staged files

## Project Conventions

### Naming & File Organization
- **Apex**: `ServiceNameService.cls` with `@AuraEnabled` methods (all public static)
- **LWC**: Component folder = component name (`returnRequestIntake/` contains `.js`, `.html`, `.css`, `-meta.xml`)
- **DTOs**: Inner classes in service (e.g., `ReturnRequestDTO`, `TriageRecommendation`)

### Code Patterns
1. **DTO Pattern**: Incoming data wrapped in DTO classes with `@AuraEnabled` properties for AuraEnabled serialization
2. **Bulk-Safe Database**: Use `Database.insert()`, `Database.update()` with `SaveResult` checks (not DML statements)
3. **Error Handling**: Throw `AuraHandledException` with user-friendly messages; front-end catches as `e.body.message`
4. **Caching**: 
   - `@AuraEnabled(cacheable=true)` for read-only queries (getReturnRequests, getReturnRequestDetails)
   - `@AuraEnabled(cacheable=false)` for mutations (createReturnRequest, updateStatus)

### LWC Patterns
- Use `@track` for reactive state properties
- Arrow functions for event handlers to preserve `this` context
- Fetch via `import methodName from '@salesforce/apex/ClassName.methodName'` then call as async
- Toast notifications: `ShowToastEvent` for user feedback

## Integration Points & Data Flow

### Return Request Creation Flow
1. User fills intake form (LWC: `returnRequestIntake`)
2. Form builds `ReturnRequestDTO` payload with customer data + array of items
3. Calls `ReturnRequestService.createReturnRequest()` (Apex)
4. Service validates, inserts parent + children, returns record ID
5. Front-end navigates to detail view or success toast

### Triage Recommendation Flow
1. Management console (LWC: `returnManagementConsole`) displays request
2. User clicks "Get Recommendation"
3. Calls `ReturnRequestService.getTriageRecommendation(recordId)`
4. Service calculates risk score based on items + customer history (30-day lookback)
5. Returns DTO with recommendation, risk score, signals, suggested actions

### Return Request List
- LWC: `returnRequestList` queries `getReturnRequests(limitSize)` 
- Supports client-side filtering by status (`Status__c` picklist)
- Open action navigates to record detail in Salesforce UI

## Key Files Reference

| File | Purpose |
|------|---------|
| [ReturnRequestService.cls](../force-app/main/default/classes/ReturnRequestService.cls) | Core Apex service with all business logic & triage system |
| [returnRequestIntake.js](../force-app/main/default/lwc/returnRequestIntake/returnRequestIntake.js) | Form component for submitting new return requests |
| [returnRequestList.js](../force-app/main/default/lwc/returnRequestList/returnRequestList.js) | List view with status filtering & row actions |
| [returnManagementConsole.js](../force-app/main/default/lwc/returnManagementConsole/returnManagementConsole.js) | Dashboard displaying return & triage recommendations |
| [package.json](../package.json) | npm scripts, dev dependencies (jest, eslint, prettier) |
| [production_readiness_checklist.md](../production_readiness_checklist.md) | Verification of service layer completeness vs test coverage |

## Custom Objects Schema

**Return_Request__c**
- `Customer_Name__c` (Text, required)
- `Customer_Email__c` (Email, required)
- `Order_Number__c` (Text, unique constraint, required)
- `Reason__c` (Picklist: Wrong Size, Damaged, Not as Described, Changed Mind, Other)
- `Status__c` (Picklist: New, Under Review, Approved, Rejected, Completed)
- `Requested_At__c` (DateTime)
- `Total_Items__c` & `Total_Refund_Amount__c` (rollup fields, optional)

**Return_Item__c** (child of Return_Request__c via `Return_Request__c` lookup)
- `SKU__c`, `Product_Name__c`, `Quantity__c`, `Unit_Price__c`, `Refund_Amount__c`, `Condition__c` (Unopened, Opened, Damaged)

## When Adding Features

1. **Service-first approach**: Add Apex method to `ReturnRequestService` with DTO inputs/outputs, proper validation
2. **Bulk-safe mandatory**: Use `Database` methods, not DML statements
3. **Test coverage required**: Add corresponding test in `ReturnRequestServiceTest.cls`
4. **LWC consumption**: Import and call service method, handle `e.body.message` errors
5. **Code format before commit**: `npm run prettier` ensures consistent style
