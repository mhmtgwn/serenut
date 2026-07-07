// server/ecosystem.config.js
// PM2 Clustering & Process Lifecycle Management
// Blueprint: Production Deployment Sprint (Clustering & Auto-Restart)

module.exports = {
  apps: [
    {
      name: 'serenut-backend',
      script: './dist/server.js',
      instances: 'max',       // Utilize all available CPU cores in cluster mode
      exec_mode: 'cluster',    // Cluster execution mode
      watch: false,
      max_memory_restart: '1G', // Restart process if RAM exceeds 1GB to prevent leaks
      env: {
        NODE_ENV: 'production',
        PORT: 3000
      },
      env_development: {
        NODE_ENV: 'development',
        PORT: 3000
      },
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
      error_file: './logs/pm2-error.log',
      out_file: './logs/pm2-access.log',
      combine_logs: true,
      merge_logs: true
    }
  ]
};
