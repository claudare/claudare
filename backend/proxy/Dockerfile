FROM gcr.io/distroless/cc-debian13:nonroot

WORKDIR /app
# The build comes from CI/CD.
# May build here instead.
COPY --chown=nonroot:nonroot bundle/ /app/

ENV PORT=7000
EXPOSE 7000
ENTRYPOINT ["/app/bin/main"]
