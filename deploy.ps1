$LOCATION = 'East US'

# App Service Plan
$SOURCE_ASP_RG_NAME = "asp-source-rg"
$SOURCE_ASP_NAME = 'asp-source'

New-AzureRmResourceGroup -Name $SOURCE_ASP_RG_NAME -Location $LOCATION

$DEPLOYMENTNAME = $SOURCE_ASP_RG_NAME + "-deployment"
$OUTPUT = New-AzureRmResourceGroupDeployment -ResourceGroupName $SOURCE_ASP_RG_NAME `
                                             -Name $DEPLOYMENTNAME `
                                             -TemplateFile .\deploy.asp.json `
                                             -TemplateParameterObject @{ ASP_NAME = $SOURCE_ASP_NAME } `
                                             -Mode Incremental `
                                             -Force       

# Web App in separate Resource Group then its App Service Plan
$WEB_APP_NAME = 'brisebois-demo-app'

$ASP_ID = $OUTPUT.Outputs.asp_id.Value

$APP_RG = 'app-rg'
New-AzureRmResourceGroup -Name $APP_RG -Location $LOCATION

$DEPLOYMENTNAME = $APP_RG + "-deployment"

New-AzureRmResourceGroupDeployment -ResourceGroupName $APP_RG `
                                   -Name $DEPLOYMENTNAME `
                                   -TemplateFile .\deploy.web-app.json `
                                   -TemplateParameterObject @{ DSN_PREFIX = $WEB_APP_NAME; ASP_ID = $ASP_ID } `
                                   -Mode Incremental `
                                   -Force    


############ Moving (Cloning) Web App to Target Service Plan

# MAKE Target App Service Plan
$TARGET_ASP_RG_NAME = "asp-target-rg"
$TARGET_ASP_NAME = 'asp-target'

New-AzureRmResourceGroup -Name $TARGET_ASP_RG_NAME -Location $LOCATION

$DEPLOYMENTNAME = $TARGET_ASP_RG_NAME + "-deployment"
New-AzureRmResourceGroupDeployment -ResourceGroupName $TARGET_ASP_RG_NAME `
                                   -Name $DEPLOYMENTNAME `
                                   -TemplateFile .\deploy.asp.json `
                                   -TemplateParameterObject @{ ASP_NAME = $TARGET_ASP_NAME; ASP_SKU = 'S3' } `
                                   -Mode Incremental `
                                   -Force       


# MAKE Source SKU P1 prior to Clone
Set-AzureRmAppServicePlan -ResourceGroupName $SOURCE_ASP_RG_NAME -Name $SOURCE_ASP_NAME -Tier Premium -WorkerSize Small
Set-AzureRmAppServicePlan -ResourceGroupName $TARGET_ASP_RG_NAME -Name $TARGET_ASP_NAME -Tier Premium -WorkerSize Small

# CLONE Web App to new App Service Plan (same RG)
$TARGET_ASP = Get-AzureRmAppServicePlan -ResourceGroupName $TARGET_ASP_RG_NAME -Name $TARGET_ASP_NAME
$ASP_ID = $TARGET_ASP.Id

# ADD '-v2' to original Web App name
$TARGET_APP_NAME = $WEB_APP_NAME + '-v2'

$SOURCE_APP = Get-AzureRmWebApp -ResourceGroupName $APP_RG -Name $WEB_APP_NAME
$SOURCE_WEB_APP_ID = $SOURCE_APP.Id

New-AzureRmResourceGroupDeployment -ResourceGroupName $APP_RG `
                                   -Name $TARGET_APP_NAME `
                                   -TemplateFile .\deploy.web-app.clone.json `
                                   -TemplateParameterObject @{ DSN_PREFIX = $TARGET_APP_NAME; ASP_ID = $ASP_ID; SOURCE_WEB_APP_ID=$SOURCE_WEB_APP_ID; } `
                                   -Mode Incremental `
                                   -Force   

## CLEAN UP

# DELETE source Web App
Remove-AzureRmWebApp -ResourceGroupName $APP_RG -Name $WEB_APP_NAME -Force

# DELETE source App Service Plan
Remove-AzureRmAppServicePlan -ResourceGroupName $SOURCE_ASP_RG_NAME -Name $SOURCE_ASP_NAME -Force

# DELETE source Resource Group
Remove-AzureRmResourceGroup -Name $SOURCE_ASP_RG_NAME -Force

# SCALE DOWN Target App Service Plan
Set-AzureRmAppServicePlan -ResourceGroupName $TARGET_ASP_RG_NAME -Name $TARGET_ASP_NAME -Tier Standard -WorkerSize Large