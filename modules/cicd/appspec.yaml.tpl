version: 0.0
Resources:
  - TargetService:
      Type: AWS::ECS::Service
      Properties:
        TaskDefinition: <TASK_DEFINITION>
        LoadBalancerInfo:
          ContainerName: "${container_name}"
          ContainerPort: ${container_port}
%{ if before_allow_traffic_lambda != "" ~}
Hooks:
  # AfterAllowTraffic: runs ONLY after CodeDeploy successfully swaps the
  # production listener (HTTPS:443) to green. The Lambda then aligns HTTP:80.
  #
  # Why not BeforeAllowTraffic? If we ran the Lambda before the swap, a
  # deployment that aborts (bad image, alarm fires, health check fails)
  # would leave port 80 stranded on the failed green target group while
  # CodeDeploy successfully reverted port 443 to blue. API Gateway uses
  # port 80, so users would see 503s even though CodeDeploy "rolled back."
  #
  # AfterAllowTraffic only fires on a successful traffic shift, so on
  # any failure path the Lambda never runs and both listeners stay
  # aligned on blue (the old, healthy target group).
  - AfterAllowTraffic: "${before_allow_traffic_lambda}"
%{ endif ~}
