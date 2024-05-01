############################################################################################################
#                                               Root Area                                                  #
############################################################################################################

# Resource Group
resource "azurerm_resource_group" "resource_group" {
  name     = "rg-${var.workload}-${var.region_short}-01"
  location = var.region
}

# Virtual Network
resource "azurerm_virtual_network" "virtual_network" {
  name                = "vnet-${var.workload}-${var.region_short}-01"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  address_space       = ["8.18.128.0/22"]
}

############################################################################################################
#                                              AKS Area                                                    #
############################################################################################################

# AKS Subnet
resource "azurerm_subnet" "aks_subnet" {
  name                 = "subnet-${var.workload}-${var.region_short}-01"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = ["8.18.128.0/24"]
}

# Container Registry
resource "azurerm_container_registry" "container_registry" {
  name                = "acr${var.workload}${var.region_short}01"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Kubernetes Cluster
resource "azurerm_kubernetes_cluster" "kubernetes_cluster" {
  name                = "aks-${var.workload}-${var.region_short}-01"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  dns_prefix          = "aks-${var.workload}-${var.region_short}-01"

  default_node_pool {
    name           = "default"
    node_count     = 1
    vm_size        = "Standard_D4s_v3"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
    max_pods       = 110
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = "10.0.2.0/24"
    dns_service_ip = "10.0.2.4"
  }

  identity {
    type = "SystemAssigned"
  }

  #Creation of namespace and enabling Azure ML extension


}

# AKS & ACR Integration
resource "azurerm_role_assignment" "role_assignment" {
  scope                = azurerm_container_registry.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.kubernetes_cluster.identity[0].principal_id
}

############################################################################################################
#                                           Azure ML Area                                                  #
############################################################################################################

# Compute Instance Subnet
resource "azurerm_subnet" "compute_subnet" {
  name                 = "subnet-${var.workload}-${var.region_short}-02"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = ["8.18.129.0/24"]
}

# Application Insights
resource "azurerm_application_insights" "application_insights" {
  name                = "appins-${var.workload}-${var.region_short}-01"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  application_type    = "web"
}

# Key Vault
resource "azurerm_key_vault" "key_vault" {
  name                = "kv-${var.workload}-${var.region_short}-01"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  tenant_id           = "e4e34038-ea1f-4882-b6e8-ccd776459ca0"
  sku_name            = "standard"


  access_policy {
    tenant_id = "e4e34038-ea1f-4882-b6e8-ccd776459ca0"
    object_id = azurerm_user_assigned_identity.ua-identity.principal_id

    key_permissions = [
      "Get",
      "List",
    ]

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
    ]
  }
}

# Storage Account
resource "azurerm_storage_account" "storage_account" {
  name                     = "st${var.workload}${var.region_short}01"
  resource_group_name      = azurerm_resource_group.resource_group.name
  location                 = azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Azure Machine Learning Workspace
resource "azurerm_machine_learning_workspace" "machine_learning_workspace" {
  name                          = "mlws-${var.workload}-${var.region_short}-01"
  location                      = azurerm_resource_group.resource_group.location
  resource_group_name           = azurerm_resource_group.resource_group.name
  application_insights_id       = azurerm_application_insights.application_insights.id
  key_vault_id                  = azurerm_key_vault.key_vault.id
  storage_account_id            = azurerm_storage_account.storage_account.id
  public_network_access_enabled = true
  container_registry_id         = azurerm_container_registry.container_registry.id
  identity {
    type = "SystemAssigned"
  }
}

# Azure Machine Learning Compute
resource "azurerm_machine_learning_compute_instance" "machine_learning_compute_instance" {
  name                          = "mlci-${var.workload}"
  machine_learning_workspace_id = azurerm_machine_learning_workspace.machine_learning_workspace.id
  virtual_machine_size          = "Standard_F4s_v2"
  subnet_resource_id            = azurerm_subnet.compute_subnet.id
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.ua-identity.id]
  }
}


############################################################################################################
#                                   Azure Managed Identity and Roles                                       #
############################################################################################################

resource "azurerm_user_assigned_identity" "ua-identity" {
  name                = "ua-identity-${var.workload}-${var.region_short}-01"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
}

resource "azurerm_role_assignment" "data_scientist_role_assignment" {
  scope                = azurerm_machine_learning_workspace.machine_learning_workspace.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = azurerm_user_assigned_identity.ua-identity.principal_id

  
}


############################################################################################################
#                                         Aks Extension and Namespace                                      #
############################################################################################################

resource "null_resource" "ml_namespace_and_extension" {
  provisioner "local-exec" {
    command = <<EOF
    az account set -s ${data.azurerm_client_config.client_config.subscription_id};
    az aks get-credentials --resource-group ${azurerm_resource_group.resource_group.name} --name ${azurerm_kubernetes_cluster.kubernetes_cluster.name} --overwrite-existing;
    kubectl create namespace ns-${var.workload};
    az k8s-extension create --name extension-aks-llmops-cin-01 --extension-type Microsoft.AzureML.Kubernetes --config enableTraining=True enableInference=True inferenceRouterServiceType=LoadBalancer allowInsecureConnections=True InferenceRouterHA=False --cluster-type managedClusters --cluster-name ${azurerm_kubernetes_cluster.kubernetes_cluster.name} --resource-group ${azurerm_resource_group.resource_group.name} --scope cluster;
  EOF
  }
}


############################################################################################################
#                                         Attaching Ml-workspace to Aks                                    #
############################################################################################################


resource "null_resource" "attach_mlws_to_aks" {

  provisioner "local-exec" {
    command = "az ml compute attach --resource-group ${azurerm_resource_group.resource_group.name} --workspace-name ${azurerm_machine_learning_workspace.machine_learning_workspace.name} --type Kubernetes --name mlinfc-llmops-01 --resource-id /subscriptions/${data.azurerm_client_config.client_config.subscription_id}/resourceGroups/${azurerm_resource_group.resource_group.name}/providers/Microsoft.ContainerService/managedclusters/${azurerm_kubernetes_cluster.kubernetes_cluster.name} --identity-type UserAssigned --user-assigned-identities /subscriptions/${data.azurerm_client_config.client_config.subscription_id}/resourceGroups/${azurerm_resource_group.resource_group.name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${azurerm_user_assigned_identity.ua-identity.name} --namespace ns-${var.workload} --no-wait"
  }

  depends_on = [null_resource.ml_namespace_and_extension]
}




############################################################################################################
#                                         Prompt Flow Runtime                                              #
############################################################################################################

resource "null_resource" "prompt_runtime_create" {

  provisioner "local-exec" {
    command = <<EOF
    access_token=$(az account get-access-token --query accessToken -o tsv)
    curl --http1.1 --request POST --url 'https://ml.azure.com/api/centralindia/flow/api/subscriptions/${data.azurerm_client_config.client_config.subscription_id}/resourceGroups/${azurerm_resource_group.resource_group.name}/providers/Microsoft.MachineLearningServices/workspaces/${azurerm_machine_learning_workspace.machine_learning_workspace.name}/FlowRuntimes/${var.prompt-runtime}' -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' -d "{   \"runtimeType\": \"ComputeInstance\",\"computeInstanceName\": \"${azurerm_machine_learning_compute_instance.machine_learning_compute_instance.name}\"}"
  EOF
  }

  depends_on = [azurerm_machine_learning_compute_instance.machine_learning_compute_instance]
}


