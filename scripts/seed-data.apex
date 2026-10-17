// Run with: sf apex run --file scripts/seed-data.apex
// Safe to run more than once (accounts matched by name; vehicles and deliveries upserted by external id).

List<String> accountNames = new List<String>{ 'Acme Retail', 'Zenith Foods', 'Orbit Pharma' };
Map<String, Account> accountsByName = new Map<String, Account>();
for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :accountNames]) {
    accountsByName.put(a.Name, a);
}
List<Account> newAccounts = new List<Account>();
for (String n : accountNames) {
    if (!accountsByName.containsKey(n)) {
        newAccounts.add(new Account(Name = n));
    }
}
insert newAccounts;
for (Account a : newAccounts) {
    accountsByName.put(a.Name, a);
}

upsert new List<Vehicle__c>{
    new Vehicle__c(Name = 'TRK-12', Vehicle_Number__c = 'TRK-12'),
    new Vehicle__c(Name = 'TRK-07', Vehicle_Number__c = 'TRK-07'),
    new Vehicle__c(Name = 'TRK-99', Vehicle_Number__c = 'TRK-99')   // deliberately has no deliveries
} Vehicle__c.Vehicle_Number__c;

Date tomorrow = Date.today().addDays(1);
upsert new List<Delivery__c>{
    // TRK-12: two active, one delivered (must be ignored)
    new Delivery__c(Name = 'D-101', Delivery_Number__c = 'D-101', Account__c = accountsByName.get('Acme Retail').Id,
        Vehicle__r = new Vehicle__c(Vehicle_Number__c = 'TRK-12'), Status__c = 'In Transit', Expected_Date__c = tomorrow, Destination__c = 'Mumbai'),
    new Delivery__c(Name = 'D-102', Delivery_Number__c = 'D-102', Account__c = accountsByName.get('Zenith Foods').Id,
        Vehicle__r = new Vehicle__c(Vehicle_Number__c = 'TRK-12'), Status__c = 'Scheduled', Expected_Date__c = tomorrow, Destination__c = 'Pune'),
    new Delivery__c(Name = 'D-103', Delivery_Number__c = 'D-103', Account__c = accountsByName.get('Acme Retail').Id,
        Vehicle__r = new Vehicle__c(Vehicle_Number__c = 'TRK-12'), Status__c = 'Delivered', Expected_Date__c = Date.today(), Destination__c = 'Delhi'),
    // TRK-07: one normal, one with no customer account (must be skipped, not fatal)
    new Delivery__c(Name = 'D-201', Delivery_Number__c = 'D-201', Account__c = accountsByName.get('Orbit Pharma').Id,
        Vehicle__r = new Vehicle__c(Vehicle_Number__c = 'TRK-07'), Status__c = 'Scheduled', Expected_Date__c = tomorrow, Destination__c = 'Jaipur'),
    new Delivery__c(Name = 'D-202', Delivery_Number__c = 'D-202', Account__c = null,
        Vehicle__r = new Vehicle__c(Vehicle_Number__c = 'TRK-07'), Status__c = 'Scheduled', Expected_Date__c = tomorrow, Destination__c = 'Jaipur')
} Delivery__c.Delivery_Number__c;

System.debug('Seed data ready: ' + [SELECT COUNT() FROM Vehicle__c] + ' vehicles, ' + [SELECT COUNT() FROM Delivery__c] + ' deliveries.');
