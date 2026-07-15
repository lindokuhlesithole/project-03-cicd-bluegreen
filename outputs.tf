output "ecr_repository_url" {
  value = module.ecs.ecr_repository_url
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "pipeline_name" {
  value = module.cicd.pipeline_name
}

output "s3_source_bucket" {
  value = module.cicd.source_bucket
}

output "codebuild_project" {
  value = module.cicd.codebuild_project
}
