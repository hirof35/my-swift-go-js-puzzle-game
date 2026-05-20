package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	// ファイルサーバーの設定（index.htmlが置いてあるディレクトリを指定）
	fs := http.FileServer(http.Dir("."))
	http.Handle("/", fs)

	port := ":8080"
	fmt.Printf("🚀 パズルゲームサーバーが起動しました！\n")
	fmt.Printf("🌐 Windows/Linuxのブラウザからアクセス可能です。\n")
	fmt.Printf("👉 http://localhost%sn", port)
	fmt.Println("--------------------------------------------------")

	if err := http.ListenAndServe(port, nil); err != nil {
		log.Fatalf("🚨 サーバー強制終了: %v", err)
	}
}