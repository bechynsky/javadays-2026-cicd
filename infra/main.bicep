// Prostředí pro demo aplikaci: App Service plán (Linux) + Web App (Java 25)
// a volitelně monitoring (Log Analytics + Application Insights).
// Nasazuje se z pipeline: az deployment group create -f infra/main.bicep -p infra/main.bicepparam

targetScope = 'resourceGroup'

@description('Název webové aplikace. Musí být v Azure globálně unikátní.')
param appName string = 'javadays-${uniqueString(resourceGroup().id)}'

@description('Region, kam se prostředky nasadí.')
param location string = resourceGroup().location

@description('Název prostředí – zobrazí se i v aplikaci.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environmentName string = 'dev'

@description('Barva záhlaví aplikace (CSS barva, např. #1F6FEB).')
param themeColor string = '#1F6FEB'

@description('Zapne Application Insights (Log Analytics + Java agent v App Service).')
param enableMonitoring bool = false

@description('Velikost App Service plánu. F1 je zdarma, ale bez Always On.')
@allowed([
  'F1'
  'B1'
  'P0v3'
])
param skuName string = 'B1'

var tags = {
  project: 'javadays-2026-cicd'
  environment: environmentName
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'asp-${appName}'
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'linux'
  properties: {
    reserved: true // Linux
  }
}

// Monitoring vzniká jen když je zapnutý (DEMO krok 3)
module monitoring 'modules/monitoring.bicep' = if (enableMonitoring) {
  name: 'monitoring'
  params: {
    baseName: appName
    location: location
    tags: tags
  }
}

// Nastavení, která aplikace čte (src/main/resources/application.properties)
var appSettings = [
  {
    name: 'APP_ENVIRONMENT'
    value: environmentName
  }
  {
    name: 'APP_THEME_COLOR'
    value: themeColor
  }
  {
    name: 'APP_MONITORING'
    value: enableMonitoring ? 'true' : 'false'
  }
]

resource web 'Microsoft.Web/sites@2024-04-01' = {
  name: appName
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'JAVA|25-java25'
      alwaysOn: skuName != 'F1'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      healthCheckPath: '/actuator/health'
      appSettings: concat(appSettings, enableMonitoring ? [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: monitoring!.outputs.connectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: 'default'
        }
      ] : [])
    }
  }
}

output webAppName string = web.name
output url string = 'https://${web.properties.defaultHostName}'
