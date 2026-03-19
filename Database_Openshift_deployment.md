

#   Generate a random string for use as secret:
openssl rand -base64 32

# Create the secret named 'postgrest-secrets' with the key 'jwt-secret'
oc create secret generic postgrest-secrets \
  --from-literal=jwt-secret="your-really-long-secret-at-least-32-characters"

# Delete entire openshift database and all associated files:
helm uninstall rfc-db -n c207ac-dev

# Install openshift database from helm chart:
helm install rfc-db ./rfc-database-chart

# Update database from helm chart:
helm upgrade --install rfc-db ./rfc-database-chart