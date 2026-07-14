module.exports = {
  apps: [
    {
      name: 'serenut-backend-staging',
      script: 'dist/server.js',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      env_staging: {
        NODE_ENV: 'staging',
        PORT: 3001,
      },
    },
  ],
};
