FROM nginx:alpine
COPY . /tmp/site
RUN rm -rf /usr/share/nginx/html/* && \
    for d in /tmp/site /tmp/site/dist /tmp/site/build /tmp/site/public; do \
      if [ -f "$d/index.html" ]; then cp -r "$d/." /usr/share/nginx/html/; break; fi; \
    done && rm -rf /tmp/site
EXPOSE 80
