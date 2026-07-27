-- Check RLS policies on products table
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'products';

-- Check if RLS is enabled on products
SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE relname = 'products';
