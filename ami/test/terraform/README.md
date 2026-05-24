# e2e terraform harness

Wraps the [box terraform module](../../../terraform) to deploy a throwaway
sheesh box (default VPC, Let's Encrypt staging certs, destroyable EBS) for the
[terratest e2e](../). Driven by `e2e_test.go`; not applied by hand.

<!-- BEGIN_TF_DOCS -->
<!-- Run terraform-docs to generate the inputs/outputs table. -->
<!-- END_TF_DOCS -->
