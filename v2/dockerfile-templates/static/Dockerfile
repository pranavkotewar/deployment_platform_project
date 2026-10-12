FROM nginx:alpine
COPY . /tmp/site
RUN rm -rf /usr/share/nginx/html/* && \
    found=0; \
    for d in /tmp/site /tmp/site/dist /tmp/site/build /tmp/site/public; do \
      if [ -f "$d/index.html" ]; then cp -r "$d/." /usr/share/nginx/html/; found=1; break; fi; \
    done; \
    if [ "$found" = "0" ]; then echo "DeployForge ERROR: no index.html found (looked in root, dist, build, public)"; exit 1; fi; \
    rm -rf /tmp/site
EXPOSE 80
