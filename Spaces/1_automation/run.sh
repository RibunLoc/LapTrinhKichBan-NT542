# s3cmd
s3cmd setacl --acl-private s3://my-space-bucket

# AWS CLI (trỏ endpoint Spaces)
aws s3api put-bucket-acl \
  --bucket my-space-bucket \
  --acl private \
  --endpoint-url https://sgp1.digitaloceanspaces.com
