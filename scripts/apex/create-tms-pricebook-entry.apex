// Run after importing data/Product2-plan.json:
//   sf data import tree -p data/Product2-plan.json -o <alias>
//   sf apex run -f scripts/apex/create-tms-pricebook-entry.apex -o <alias>
// Adds Tenancy Management Software to the Standard Price Book at £2 per tenant per month.
Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'TMS-USG-MTH' LIMIT 1];
Pricebook2 std = [SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
if (!std.IsActive) { update new Pricebook2(Id = std.Id, IsActive = true); }
if ([SELECT COUNT() FROM PricebookEntry WHERE Product2Id = :p.Id AND Pricebook2Id = :std.Id] == 0) {
    insert new PricebookEntry(Pricebook2Id = std.Id, Product2Id = p.Id, UnitPrice = 2, IsActive = true);
}
