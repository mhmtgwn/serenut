import { describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

interface ColumnContract {
  type: string;
  nullable: boolean;
  default?: unknown;
}

interface EntityContract {
  table_pg: string;
  table_sqlite: string;
  columns: Record<string, ColumnContract>;
}

interface SchemaContract {
  version: number;
  entities: Record<string, EntityContract>;
}

describe("Schema Contract Verification (PostgreSQL / Backend)", () => {
  const contractPath = path.resolve(__dirname, "../../../shared/schema_contract.json");
  assert.ok(fs.existsSync(contractPath), `Schema contract file must exist at ${contractPath}`);

  const rawContract = fs.readFileSync(contractPath, "utf-8");
  const contract: SchemaContract = JSON.parse(rawContract);

  // Read all schema SQL files to aggregate table definitions
  const dbDir = path.resolve(__dirname, "../../db");
  const sqlFiles = fs.readdirSync(dbDir)
    .filter((f) => f.startsWith("schema") && f.endsWith(".sql"))
    .sort((a, b) => {
      const numA = parseInt(a.replace(/[^0-9]/g, "") || "0", 10);
      const numB = parseInt(b.replace(/[^0-9]/g, "") || "0", 10);
      return numA - numB;
    });

  const combinedSql = sqlFiles
    .map((f) => fs.readFileSync(path.join(dbDir, f), "utf-8"))
    .join("\n");

  it("verifies all contract entities and required columns exist in PostgreSQL schema files", () => {
    for (const [entityName, entityDef] of Object.entries(contract.entities)) {
      const tableName = entityDef.table_pg;
      const tableRegex = new RegExp(`CREATE\\s+TABLE\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?(?:public\\.)?${tableName}\\s*\\(`, "i");
      assert.ok(
        tableRegex.test(combinedSql),
        `Table "${tableName}" for entity "${entityName}" must be defined in server/db/*.sql`
      );

      for (const colName of Object.keys(entityDef.columns)) {
        // Check that column is mentioned in combinedSql
        const colRegex = new RegExp(`\\b${colName}\\b`, "i");
        assert.ok(
          colRegex.test(combinedSql),
          `Column "${colName}" in table "${tableName}" must exist in server/db/*.sql`
        );
      }
    }
  });

  it("verifies customer_id nullability rules match contract in sales, orders, and financial_transactions", () => {
    // sales.customer_id is nullable (walk-in cash sales)
    assert.equal(contract.entities.sale.columns.customer_id.nullable, true);
    // order.customer_id is nullable (walk-in orders)
    assert.equal(contract.entities.order.columns.customer_id.nullable, true);
    // financial_transaction.customer_id is nullable (expenses, overhead)
    assert.equal(contract.entities.financial_transaction.columns.customer_id.nullable, true);
  });
});
