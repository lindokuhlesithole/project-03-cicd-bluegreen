module "network" {
  source   = "./modules/network"
  app_name = var.app_name
}

module "ecs" {
  source             = "./modules/ecs"
  app_name           = var.app_name
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  account_id         = var.account_id
  aws_region         = var.aws_region
}

module "alb" {
  source            = "./modules/alb"
  app_name          = var.app_name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
}

module "cicd" {
  source             = "./modules/cicd"
  app_name           = var.app_name
  account_id         = var.account_id
  aws_region         = var.aws_region
  ecr_repository_url = module.ecs.ecr_repository_url
  ecs_cluster_name   = module.ecs.cluster_name
  ecs_service_name   = module.ecs.service_name
}
