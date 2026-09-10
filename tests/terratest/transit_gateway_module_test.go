package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TGW isn't emulated by MiniStack Community — validated structurally
// against the plan JSON only, same technique as iam_module_test.go
// (see ADR-0002, and this repo's README "Testing Strategy" section).
func TestTransitGatewayModulePlanEnforcesSpokeSegmentation(t *testing.T) {
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/transit-gateway",
		PlanFilePath: "terratest.tfplan",
	})

	planStruct := terraform.InitAndPlanAndShowWithStruct(t, terraformOptions)
	resourceChanges := planStruct.ResourceChangesMap

	// The TGW must fail closed: no attachment can silently inherit the
	// default route table's permissive behavior (ADR-0002).
	tgw, ok := resourceChanges["module.transit_gateway.aws_ec2_transit_gateway.this"]
	require.True(t, ok, "expected the Transit Gateway resource in the plan")
	after := tgw.Change.After.(map[string]interface{})
	assert.Equal(t, "disable", after["default_route_table_association"])
	assert.Equal(t, "disable", after["default_route_table_propagation"])

	// Each spoke gets its OWN route table — not the TGW default, not a
	// table shared with the other spoke.
	for _, spoke := range []string{"dev", "prod"} {
		rtbKey := `module.transit_gateway.aws_ec2_transit_gateway_route_table.spoke["` + spoke + `"]`
		assert.Contains(t, resourceChanges, rtbKey, "expected a dedicated route table for spoke %q", spoke)

		assocKey := `module.transit_gateway.aws_ec2_transit_gateway_route_table_association.spoke["` + spoke + `"]`
		assert.Contains(t, resourceChanges, assocKey, "expected spoke %q's attachment associated to its own table", spoke)

		spokeLearnsHubKey := `module.transit_gateway.aws_ec2_transit_gateway_route_table_propagation.spoke_learns_hub["` + spoke + `"]`
		assert.Contains(t, resourceChanges, spokeLearnsHubKey, "expected spoke %q to learn hub routes", spoke)

		hubLearnsSpokeKey := `module.transit_gateway.aws_ec2_transit_gateway_route_table_propagation.hub_learns_spokes["` + spoke + `"]`
		assert.Contains(t, resourceChanges, hubLearnsSpokeKey, "expected hub to learn spoke %q's routes for return traffic", spoke)
	}

	// The actual point of ADR-0002: exactly 4 propagation resources exist
	// (2 hub_learns_spokes + 2 spoke_learns_hub). There is no third
	// propagation resource anywhere that would link one spoke's
	// attachment into the OTHER spoke's route table — if someone
	// reintroduces that, this count catches it even though nothing
	// above names the bad key directly.
	propagationCount := 0
	for addr := range resourceChanges {
		if addr == `module.transit_gateway.aws_ec2_transit_gateway_route_table_propagation.hub_learns_spokes["dev"]` ||
			addr == `module.transit_gateway.aws_ec2_transit_gateway_route_table_propagation.hub_learns_spokes["prod"]` ||
			addr == `module.transit_gateway.aws_ec2_transit_gateway_route_table_propagation.spoke_learns_hub["dev"]` ||
			addr == `module.transit_gateway.aws_ec2_transit_gateway_route_table_propagation.spoke_learns_hub["prod"]` {
			propagationCount++
		}
	}
	assert.Equal(t, 4, propagationCount, "expected exactly 4 propagation resources — dev and prod each learn only the hub, never each other")
}