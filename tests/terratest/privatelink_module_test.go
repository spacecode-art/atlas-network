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