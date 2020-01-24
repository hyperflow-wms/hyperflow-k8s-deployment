hf-pod-name() {
  sudo kubectl get pods -lcomponent=hyperflow-engine -o jsonpath='{.items..metadata.name}'
}
hf-exec() {
  sudo kubectl exec -it $(hf-pod-name) -c hyperflow sh 
}
hf-logs() {
  sudo kubectl logs $(hf-pod-name) -c hyperflow -f 
}

echo "Hyperflow helper functions:"
case "$SHELL" in
    *zsh)
        print -rl --  ${(k)functions} | grep --color=never hf-
        ;;
    *bash)
        declare -F | awk '{print $NF}' | grep --color=never hf-
        ;;
    *)
        echo "Not supported SHELL: $SHELL. Tho you can try :-)"
        exit 1
        ;;
esac
