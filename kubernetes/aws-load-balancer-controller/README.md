### https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html
# Install the AWS Load Balancer Controller add-on using helm

## Step 1: Configure IAM
- You only need to create an IAM Role for the AWS Load Balancer Controller one per AWS account. 
- Check if AmazonEKSLoadBalancerControllerRole exists

## Step 2: Update the helm repo
helm repo update eks

## Step 3: Install the AWS Load Balancer Controller.
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --version 1.11.0 \
  --set clusterName=ingress-eks-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::717240872783:role/AmazonEKSLoadBalancerControllerRole" \
  --set serviceAccount.name=aws-load-balancer-controller
### This adds the following CRDs:
- ingressclassparams (APIVERSION: elbv2.k8s.aws/v1beta1) (Namespaced: false)
- targetgroupbindings (APIVERSION: elbv2.k8s.aws/v1beta1) (Namespaced: true)
### and creates the following resources:
- ingressclass by the name of `alb`
- deployment
- service
- serviceaccount

## Step 4: Verify that the controller is installed
> kubectl get deployment aws-load-balancer-controller -n kube-system
> kubectl logs deploy/aws-load-balancer-controller -n kube-system