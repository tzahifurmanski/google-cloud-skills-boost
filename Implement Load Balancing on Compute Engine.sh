// =======================================================
Implement Load Balancing on Compute Engine: Challenge Lab
// =======================================================

// Cloud Shell Setup
gcloud config set compute/region us-west4
gcloud config set compute/zone us-west4-b

// Phase 1 - Creating a Jump host
// ==================================

gcloud compute instances create nucleus-jumphost-643 --machine-type=e2-micro --zone=us-west4-b



// Phase 2 - HTTP Load balancer setup
// ==================================

// Create the script locally (In the Cloud Shell)
cat << EOF > startup.sh
#! /bin/bash
apt-get update
apt-get install -y nginx
service nginx start
sed -i -- 's/nginx/Google Cloud Platform - '"\$HOSTNAME"'/' /var/www/html/index.nginx-debian.html
EOF


// Create an instance template for the load balancer, and include the above script
gcloud compute instance-templates create nucleus-lb-backend-template \
   --region=us-west4 \
   --network=default \
   --subnet=default \
   --tags=allow-health-check \
   --machine-type=e2-medium \
   --image-family=debian-11 \
   --image-project=debian-cloud \
   --metadata-from-file=startup-script=startup.sh


// Create a managed instance group based on the template. (to power the LB)
  gcloud compute instance-groups managed create nucleus-lb-backend-group \
  --template=nucleus-lb-backend-template --size=2 --zone=us-west4-b


// Set named port
gcloud compute instance-groups managed set-named-ports nucleus-lb-backend-group --named-ports http:80


// Healthcheck firewall rule (With the specific name requested - allow-tcp-rule-152)
   gcloud compute firewall-rules create allow-tcp-rule-152 \
  --network=default \
  --action=allow \
  --direction=ingress \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=allow-health-check \
  --rules=tcp:80


// Healthcheck creation
gcloud compute health-checks create http http-basic-check \
  --port 80


// Backend (including healthcheck, and HTTP support)
gcloud compute backend-services create nucleus-web-backend-service \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=http-basic-check \
  --global


// Add backend to the instance group
gcloud compute backend-services add-backend nucleus-web-backend-service \
  --instance-group=nucleus-lb-backend-group \
  --instance-group-zone=us-west4-b \
  --global


// URL map
gcloud compute url-maps create nucleus-web-map-http \
  --default-service nucleus-web-backend-service


// HTTP proxy
gcloud compute target-http-proxies create nucleus-http-lb-proxy \
    --url-map nucleus-web-map-http


// Create a static IP (To be used by the LB)
gcloud compute addresses create nucleus-lb-ipv4-1 \
  --ip-version=IPV4 \
  --global


// Forwarding rule
gcloud compute forwarding-rules create nucleus-http-content-rule \
   --address=nucleus-lb-ipv4-1\
   --global \
   --target-http-proxy=nucleus-http-lb-proxy \
   --ports=80


// Note: Need to wait for a couple of minutes until the LB is starting to work


// Optional - Confirm LB is working
IPADDRESS=$(gcloud compute addresses describe nucleus-lb-ipv4-1 \
  --format="get(address)" \
  --global)
while true; do curl -m1 $IPADDRESS; sleep 5; done