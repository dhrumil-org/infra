{
  "family": "${task_family}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["EC2"],
  "cpu": "${task_cpu}",
  "memory": "${task_memory}",
  "executionRoleArn": "${execution_role_arn}",
  "taskRoleArn": "${task_role_arn}",
  "containerDefinitions": [
    {
      "name": "${container_name}",
      "image": "<IMAGE1_NAME>",
      "cpu": ${task_cpu},
      "memory": ${task_memory},
      "essential": true,
      "portMappings": [
        {
          "containerPort": ${container_port},
          "hostPort": ${container_port},
          "protocol": "tcp"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${log_group}",
          "awslogs-region": "${aws_region}",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
