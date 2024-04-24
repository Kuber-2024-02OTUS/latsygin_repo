# адрес кластера
server=https://127.0.0.1:55298
# имя секрета SA
name=secret-sa-cd

ca=$(kubectl get secret/$name -o jsonpath='{.data.ca\.crt}')
token=$(kubectl get secret/$name -o jsonpath='{.data.token}' | base64 --decode)
namespace=$(kubectl get secret/$name -o jsonpath='{.data.namespace}' | base64 --decode)

echo "
apiVersion: v1
kind: Config
clusters:
- name: minikube-cluster
  cluster:
    certificate-authority-data: ${ca}
    server: ${server}
contexts:
- name: minikube-context
  context:
    cluster: minikube-cluster
    namespace: homework
    user: minikube-user
current-context: minikube-context
users:
- name: minikube-user
  user:
    token: ${token}
" > sa.kubeconfig