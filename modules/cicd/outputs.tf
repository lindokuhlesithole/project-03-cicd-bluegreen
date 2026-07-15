output "pipeline_name" {
  value = aws_codepipeline.main.name
}

output "codebuild_project" {
  value = aws_codebuild_project.main.name
}

output "source_bucket" {
  value = aws_s3_bucket.source.bucket
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}
