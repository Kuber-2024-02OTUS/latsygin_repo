# Описание задания №9
## Что здесь происходит?
Разворачивается инфраструктура в Яндекс.Облоко (k8s-cluster из двух нод + s3-bucket)
В кластер деплоятся сервисы: Grafana (с добавлением датасорса Loki) + Loki (с сохранением данных в s3) + Promtail
Настраивается сбор логов с сервисов кластера через Loki.

## Выполнение задания №9
Инфраструктура разворачивается с помощью [Terraform](https://terraform-provider.yandexcloud.net/).
1. Установить terraform.
2. Инициализировать провайдер yandex-cloud/yandex. 
3. Установить значения для переменных, которые определяют доступ к Yandex.Cloud и путь до публичного ключа(используется для доступа на хосты созданного k8s кластера):
	```bash
	cloud_id        = ""  
	folder_id       = ""  
	token           = ""  
	public_key_path = ""
	```
4. Развернуть инфраструктуру:
```bash
cd terraform/
terraform validate  #проверка конфигурации
terraform plan      #план
terraform apply     #применение
```
5. Подключить созданный кластер в локальный конфиг:
```bash
yc managed-kubernetes cluster get-credentials --external --name tf-k8s --force
```
6. Получить в ENV-переменные ключи доступа к бакету:
```bash
export YC_ACCESS_KEY=$(terraform output -json | jq .access_key.value | sed "s/\"//g")
export YC_SECRET_KEY=$(terraform output -json | jq .secret_key.value | sed "s/\"//g")
```
7. Задеплоить в k8s-кластер сервисы (grafana, loki, promtail):
```bash
# деплоим через helmfile и werf
cd helm/
export WERF_HELM3_MODE=1
helmfile -b werf apply -n monitoring --set loki.storage.s3.accessKeyId=$YC_ACCESS_KEY --set loki.storage.s3.secretAccessKey=$YC_SECRET_KEY
```
8. Получить логин и пароль для графаны
```bash
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-user}" | base64 --decode ; echo
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```
9. Проверка работоспособности:
Проброс портов (доступ до UI графаны)
```bash
kubectl --namespace monitoring port-forward service/grafana 3000:80
```
Открыть в браузере URL http://127.0.0.1:3000/
