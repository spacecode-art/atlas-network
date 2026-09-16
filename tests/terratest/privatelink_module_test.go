package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// PrivateLink Interface Endpoints aren't emulated by MiniStack Community —
// validated structurally against the plan JSON only, same technique as
// transit_gateway_module_test.go (see ADR-0003, and this repo's README
// "Testing Strategy" section).
func TestPrivateLinkModulePlanEnforcesInterfaceOnlyAndScopedIngress(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/privatelink",
		PlanFilePath: "terratest.tfplan",
	})

	planStruct := terraform.InitAndPlanAndShowWithStruct(t, terraformOptions)
	resourceChanges := planStruct.ResourceChangesMap

	// The core of ADR-0003: this must be an Interface endpoint. A Gateway
	// endpoint is not PrivateLink — if a future edit ever changes this
	// module to accept vpc_endpoint_type as a variable and someone passes
	// "Gateway", this test fails instead of the README quietly becoming
	// wrong.
	endpoint, ok := resourceChanges["module.privatelink.aws_vpc_endpoint.this"]
	require.True(t, ok, "expected the VPC Endpoint resource in the plan")
	endpointAfter := endpoint.Change.After.(map[string]interface{})
	assert.Equal(t, "Interface", endpointAfter["vpc_endpoint_type"],
		"endpoint must be Interface type — Gateway endpoints are not PrivateLink, see ADR-0003")

	// The security group must exist and must NOT default to 0.0.0.0/0.
	// This is the assertion that actually matters: validate/fmt would
	// never catch a widened default, only a value-level check like this
	// one does.
	sg, ok := resourceChanges["module.privatelink.aws_security_group.endpoint"]
	require.True(t, ok, "expected the endpoint security group in the plan")
	sgAfter := sg.Change.After.(map[string]interface{})

	ingressRules, ok := sgAfter["ingress"].([]interface{})
	require.True(t, ok, "expected ingress to be present on the security group")
	require.Len(t, ingressRules, 1, "expected exactly one ingress rule")

	ingressRule := ingressRules[0].(map[string]interface{})
	cidrBlocks, ok := ingressRule["cidr_blocks"].([]interface{})
	require.True(t, ok, "expected cidr_blocks on the ingress rule")

	for _, cidr := range cidrBlocks {
		assert.NotEqual(t, "0.0.0.0/0", cidr,
			"security group ingress must never default to 0.0.0.0/0 — scope to the consuming spoke's CIDR")
	}

	// Egress must be explicitly empty, not merely absent — matches the
	// locked-down pattern documented in this module's main.tf.
	egressRules, ok := sgAfter["egress"].([]interface{})
	require.True(t, ok, "expected egress key to be present (even if empty)")
	assert.Len(t, egressRules, 0, "expected no egress rules — the endpoint ENI only receives inbound HTTPS")
}

// This test locks in the ADR-0007 fix: when create_gateway_endpoint is
// true, the module must produce a Gateway-type endpoint as a prerequisite
// for the Interface endpoint's private_dns_enabled setting. Without this
// resource in the plan, AWS rejects private_dns_enabled=true for S3 at
// apply time — exactly the failure ADR-0007 documents, and one this
// module's original test suite had no way to catch since the fixture
// never set create_gateway_endpoint.
func TestPrivateLinkModuleCreatesGatewayEndpointPrerequisiteWhenRequested(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/privatelink-with-gateway-prereq",
		PlanFilePath: "terratest.tfplan",
	})

	planStruct := terraform.InitAndPlanAndShowWithStruct(t, terraformOptions)
	resourceChanges := planStruct.ResourceChangesMap

	gateway, ok := resourceChanges["module.privatelink.aws_vpc_endpoint.gateway_prerequisite[0]"]
	require.True(t, ok, "expected the Gateway endpoint prerequisite in the plan when create_gateway_endpoint = true")
	gatewayAfter := gateway.Change.After.(map[string]interface{})
	assert.Equal(t, "Gateway", gatewayAfter["vpc_endpoint_type"],
		"the prerequisite endpoint must be Gateway type — this is the ADR-0007 fix, not a violation of ADR-0003's Interface-only rule for the module's primary output")

	interfaceEndpoint, ok := resourceChanges["module.privatelink.aws_vpc_endpoint.this"]
	require.True(t, ok, "expected the Interface endpoint in the plan")
	interfaceAfter := interfaceEndpoint.Change.After.(map[string]interface{})
	assert.Equal(t, "Interface", interfaceAfter["vpc_endpoint_type"],
		"the module's primary endpoint must still be Interface type — ADR-0003 unchanged")
}