FROM node:20-alpine

ENV NODE_ENV=production
WORKDIR /agent
COPY index.js ./index.js

EXPOSE 3070
CMD ["node", "index.js"]
