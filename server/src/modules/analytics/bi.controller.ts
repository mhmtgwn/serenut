import { Router, Response } from 'express';
import { pgPool } from '../../config/database';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { logger } from '../../config/logger';

const router = Router();

// ── SQL TRANSACTION HELPER FOR TENANT CONTEXT ──────────────────────────────
async function runWithTenantContext(companyId: string, fn: (client: any) => Promise<any>) {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SET LOCAL app.current_company_id = $1', [companyId]);
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * @openapi
 * /api/v1/analytics/dashboard:
 *   get:
 *     summary: Get dashboard KPIs (Today, Week, Month, Top product, busiest hour)
 *     security:
 *       - BearerAuth: []
 *     responses:
 *       200:
 *         description: Dashboard KPIs payload
 */
router.get('/dashboard', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  
  try {
    const data = await runWithTenantContext(user.company_id, async (client) => {
      // 1. Today metrics
      const todayRes = await client.query(`
        SELECT 
          COALESCE(SUM(total_amount), 0) as revenue,
          COUNT(*) as orders
        FROM sales
        WHERE created_at >= CURRENT_DATE AND is_deleted = FALSE
      `);

      // 2. Weekly metrics
      const weekRes = await client.query(`
        SELECT COALESCE(SUM(total_amount), 0) as revenue
        FROM sales
        WHERE created_at >= NOW() - INTERVAL '7 days' AND is_deleted = FALSE
      `);

      // 3. Monthly metrics
      const monthRes = await client.query(`
        SELECT COALESCE(SUM(total_amount), 0) as revenue
        FROM sales
        WHERE created_at >= NOW() - INTERVAL '30 days' AND is_deleted = FALSE
      `);

      // 4. Top selling product
      const topProdRes = await client.query(`
        SELECT p.name, SUM(si.quantity) as qty
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        JOIN products p ON si.product_id = p.id
        WHERE s.created_at >= NOW() - INTERVAL '30 days' AND s.is_deleted = FALSE
        GROUP BY p.name
        ORDER BY qty DESC
        LIMIT 1
      `);

      // 5. Busiest hour
      const busiestHourRes = await client.query(`
        SELECT EXTRACT(HOUR FROM created_at) as hour, COUNT(*) as count
        FROM sales
        WHERE created_at >= NOW() - INTERVAL '30 days' AND is_deleted = FALSE
        GROUP BY hour
        ORDER BY count DESC
        LIMIT 1
      `);

      // 6. Payment method breakdown
      const payBreakdown = await client.query(`
        SELECT payment_method, COUNT(*) as count, COALESCE(SUM(total_amount), 0) as total
        FROM sales
        WHERE created_at >= NOW() - INTERVAL '30 days' AND is_deleted = FALSE
        GROUP BY payment_method
      `);

      const breakdownMap: Record<string, number> = { cash: 0, card: 0, credit: 0 };
      let totalSalesCount = 0;
      
      for (const row of payBreakdown.rows) {
        const method = row.payment_method.toLowerCase();
        const count = parseInt(row.count, 10);
        totalSalesCount += count;
        if (method.includes('cash') || method.includes('nakit')) {
          breakdownMap.cash += count;
        } else if (method.includes('card') || method.includes('kart') || method.includes('credit_card')) {
          breakdownMap.card += count;
        } else {
          breakdownMap.credit += count;
        }
      }

      // Convert breakdown count to percentages
      const pctBreakdown = { cash: 0, card: 0, credit: 0 };
      if (totalSalesCount > 0) {
        pctBreakdown.cash = Math.round((breakdownMap.cash / totalSalesCount) * 100);
        pctBreakdown.card = Math.round((breakdownMap.card / totalSalesCount) * 100);
        pctBreakdown.credit = Math.round((breakdownMap.credit / totalSalesCount) * 100);
      }

      const todayRevenue = parseFloat(todayRes.rows[0].revenue);
      const todayOrders = parseInt(todayRes.rows[0].orders, 10);
      const avgBasket = todayOrders > 0 ? Math.round(todayRevenue / todayOrders) : 0;

      return {
        today: {
          revenue: todayRevenue,
          orders: todayOrders,
          avgBasket
        },
        week: {
          revenue: parseFloat(weekRes.rows[0].revenue),
          growth_pct: 5.4 // Placeholder for comparison
        },
        month: {
          revenue: parseFloat(monthRes.rows[0].revenue),
          growth_pct: 12.8
        },
        topProduct: topProdRes.rows.length > 0 ? {
          name: topProdRes.rows[0].name,
          qty: parseFloat(topProdRes.rows[0].qty)
        } : null,
        busiestHour: busiestHourRes.rows.length > 0 ? parseInt(busiestHourRes.rows[0].hour, 10) : null,
        paymentBreakdown: pctBreakdown
      };
    });

    return res.json(data);
  } catch (err) {
    logger.error('Failed to retrieve dashboard analytics:', err);
    return res.status(500).json({ error: 'server_error', message: 'Veri analizi esnasında hata oluştu.' });
  }
});

/**
 * @openapi
 * /api/v1/analytics/sales-trend:
 *   get:
 *     summary: Retrieve sales trend dataset
 *     security:
 *       - BearerAuth: []
 */
router.get('/sales-trend', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const period = (req.query.period as string) || 'daily';

  try {
    const list = await runWithTenantContext(user.company_id, async (client) => {
      let intervalSql = "DATE_TRUNC('day', created_at)";
      let limitDays = 30;

      if (period === 'hourly') {
        intervalSql = "DATE_TRUNC('hour', created_at)";
        limitDays = 1; // Last 24 hours
      } else if (period === 'weekly') {
        intervalSql = "DATE_TRUNC('week', created_at)";
        limitDays = 12 * 7; // Last 12 weeks
      } else if (period === 'monthly') {
        intervalSql = "DATE_TRUNC('month', created_at)";
        limitDays = 365; // Last 12 months
      }

      const resTrend = await client.query(`
        SELECT 
          ${intervalSql} as label_time,
          COALESCE(SUM(total_amount), 0) as total_revenue,
          COUNT(*) as sales_count
        FROM sales
        WHERE created_at >= NOW() - INTERVAL '${limitDays} days' AND is_deleted = FALSE
        GROUP BY label_time
        ORDER BY label_time ASC
      `);

      return resTrend.rows.map((row: any) => ({
        time: row.label_time,
        revenue: parseFloat(row.total_revenue),
        count: parseInt(row.sales_count, 10)
      }));
    });

    return res.json(list);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/analytics/products:
 *   get:
 *     summary: Retrieve product analytics (Revenue, units sold, stock velocity)
 *     security:
 *       - BearerAuth: []
 */
router.get('/products', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const sortBy = (req.query.sort as string) || 'revenue'; // 'revenue' | 'quantity'

  try {
    const list = await runWithTenantContext(user.company_id, async (client) => {
      const query = `
        SELECT 
          p.id, 
          p.name, 
          p.category,
          p.quantity as stock_quantity,
          COALESCE(SUM(si.quantity), 0) as units_sold,
          COALESCE(SUM(si.subtotal), 0) as revenue
        FROM products p
        LEFT JOIN sale_items si ON si.product_id = p.id
        LEFT JOIN sales s ON si.sale_id = s.id AND s.is_deleted = FALSE
        WHERE p.is_deleted = FALSE
        GROUP BY p.id, p.name, p.category, p.quantity
        ORDER BY ${sortBy === 'quantity' ? 'units_sold' : 'revenue'} DESC
        LIMIT 50
      `;
      const prodRes = await client.query(query);
      return prodRes.rows.map((row: any) => ({
        id: row.id,
        name: row.name,
        category: row.category,
        stock: parseInt(row.stock_quantity, 10),
        unitsSold: parseFloat(row.units_sold),
        revenue: parseFloat(row.revenue)
      }));
    });
    return res.json(list);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/analytics/stock:
 *   get:
 *     summary: Get stock intelligence (Low stock warnings, turnover speed)
 *     security:
 *       - BearerAuth: []
 */
router.get('/stock', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const data = await runWithTenantContext(user.company_id, async (client) => {
      // 1. Critical stock (items below 10 qty threshold)
      const criticalRes = await client.query(`
        SELECT id, name, category, quantity
        FROM products
        WHERE quantity <= 10 AND is_deleted = FALSE
        ORDER BY quantity ASC
        LIMIT 20
      `);

      // 2. Low stock count
      const lowCountRes = await client.query(`
        SELECT COUNT(*) FROM products WHERE quantity <= 5 AND is_deleted = FALSE
      `);

      return {
        criticalItems: criticalRes.rows.map((row: any) => ({
          id: row.id,
          name: row.name,
          category: row.category,
          quantity: parseInt(row.quantity, 10)
        })),
        criticalCount: parseInt(lowCountRes.rows[0].count, 10)
      };
    });
    return res.json(data);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/analytics/finance:
 *   get:
 *     summary: Finance hub reports (Veresiye debt, collections, receivables)
 *     security:
 *       - BearerAuth: []
 */
router.get('/finance', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const data = await runWithTenantContext(user.company_id, async (client) => {
      // 1. Total Debt (alacak)
      const totalReceivableRes = await client.query(`
        SELECT COALESCE(SUM(balance), 0) as balance FROM customers WHERE balance > 0 AND is_deleted = FALSE
      `);

      // 2. Total Credit (borç)
      const totalPayableRes = await client.query(`
        SELECT COALESCE(SUM(balance), 0) as balance FROM customers WHERE balance < 0 AND is_deleted = FALSE
      `);

      // 3. Top debtors list
      const topDebtors = await client.query(`
        SELECT id, name, phone, balance
        FROM customers
        WHERE balance > 0 AND is_deleted = FALSE
        ORDER BY balance DESC
        LIMIT 10
      `);

      return {
        receivables: parseFloat(totalReceivableRes.rows[0].balance),
        payables: Math.abs(parseFloat(totalPayableRes.rows[0].balance)),
        topDebtors: topDebtors.rows.map((row: any) => ({
          id: row.id,
          name: row.name,
          phone: row.phone,
          balance: parseFloat(row.balance)
        }))
      };
    });
    return res.json(data);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/analytics/branches:
 *   get:
 *     summary: Branch comparison revenue data
 *     security:
 *       - BearerAuth: []
 */
router.get('/branches', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const list = await runWithTenantContext(user.company_id, async (client) => {
      const query = `
        SELECT 
          s.id, 
          s.name, 
          COALESCE(SUM(sl.total_amount), 0) as total_revenue,
          COUNT(sl.id) as order_count
        FROM stores s
        LEFT JOIN devices d ON d.store_id = s.id
        LEFT JOIN sales sl ON sl.created_by = d.id AND sl.is_deleted = FALSE
        GROUP BY s.id, s.name
        ORDER BY total_revenue DESC
      `;
      const branchRes = await client.query(query);
      return branchRes.rows.map((row: any) => ({
        id: row.id,
        name: row.name,
        revenue: parseFloat(row.total_revenue),
        orders: parseInt(row.order_count, 10)
      }));
    });
    return res.json(list);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/analytics/staff:
 *   get:
 *     summary: Retrieve staff/cashier performance metrics
 *     security:
 *       - BearerAuth: []
 */
router.get('/staff', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const list = await runWithTenantContext(user.company_id, async (client) => {
      const query = `
        SELECT 
          u.id, 
          u.name,
          COUNT(s.id) as sales_count,
          COALESCE(SUM(s.total_amount), 0) as total_revenue
        FROM users u
        LEFT JOIN sales s ON s.created_by = u.id AND s.is_deleted = FALSE
        WHERE u.company_id = $1 AND u.is_active = TRUE
        GROUP BY u.id, u.name
        ORDER BY total_revenue DESC
      `;
      // Running directly under tenant context
      const staffRes = await client.query(query, [user.company_id]);
      return staffRes.rows.map((row: any) => ({
        id: row.id,
        name: row.name,
        salesCount: parseInt(row.sales_count, 10),
        revenue: parseFloat(row.total_revenue)
      }));
    });
    return res.json(list);
  } catch (err) {
    console.error('Staff analytics error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/analytics/export:
 *   get:
 *     summary: Export reports as CSV
 *     security:
 *       - BearerAuth: []
 */
router.get('/export', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const type = (req.query.type as string) || 'sales'; // 'sales' | 'products' | 'debtors'

  try {
    const csvContent = await runWithTenantContext(user.company_id, async (client) => {
      if (type === 'products') {
        const prodRes = await client.query(`
          SELECT name, category, quantity, price FROM products WHERE is_deleted = FALSE
        `);
        let csv = 'Product Name,Category,Quantity,Price\n';
        for (const row of prodRes.rows) {
          csv += `"${row.name.replace(/"/g, '""')}","${(row.category || '').replace(/"/g, '""')}",${row.quantity},${row.price}\n`;
        }
        return csv;
      } else if (type === 'debtors') {
        const debtRes = await client.query(`
          SELECT name, phone, balance FROM customers WHERE balance > 0 AND is_deleted = FALSE
        `);
        let csv = 'Customer Name,Phone,Debt Balance\n';
        for (const row of debtRes.rows) {
          csv += `"${row.name.replace(/"/g, '""')}","${row.phone || ''}",${row.balance}\n`;
        }
        return csv;
      } else {
        // Default sales log
        const salesRes = await client.query(`
          SELECT id, total_amount, paid_amount, payment_method, created_at FROM sales WHERE is_deleted = FALSE ORDER BY created_at DESC LIMIT 500
        `);
        let csv = 'Sale ID,Total Amount,Paid Amount,Payment Method,Created At\n';
        for (const row of salesRes.rows) {
          csv += `"${row.id}",${row.total_amount},${row.paid_amount},"${row.payment_method}",${row.created_at.toISOString()}\n`;
        }
        return csv;
      }
    });

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename="report-${type}-${Date.now()}.csv"`);
    return res.send(csvContent);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
