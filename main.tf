module "iosxe" {
  source  = "netascode/nac-iosxe/iosxe"
  version = "0.1.0"

  yaml_directories = ["data/"]
}
