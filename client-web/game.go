package main

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http"
)

const (
	BoardSize     = 8
	CellSize      = 50.0
	SnapTolerance = 35.0 // サーバー側でも共通の吸着しきい値を保持
)

// クライアントからリアルタイムに送られてくる、ドロップした瞬間の生データ
type SnapVerificationRequest struct {
	MouseRawX   float64 `json:"mouse_raw_x"`   // 離した位置のX座標 (Canvas上のピクセル値)
	MouseRawY   float64 `json:"mouse_raw_y"`   // 離した位置のY座標
	OffsetX     float64 `json:"offset_x"`      // 掴み位置のオフセット
	OffsetY     float64 `json:"offset_y"`
	BlockType   string  `json:"block_type"`
	CurrentGrid [8][8]int `json:"current_grid"`
}

type SnapResultResponse struct {
	Success   bool   `json:"success"`
	SnappedX  int    `json:"snapped_x"`  // サーバー側で吸着判定した格子X
	SnappedY  int    `json:"snapped_y"`  // サーバー側で吸着判定した格子Y
	Message   string `json:"message"`
}

// 2次元ベクトルの距離計算（ユークリッド距離）
func calculateDistance(x1, y1, x2, y2 float64) float64 {
	return math.Hypot(x1-x2, y1-y2)
}

func handleSnapVerify(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	var req SnapVerificationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// 1. マウス位置から掴みオフセットを差し引き、ブロック原点の「生の実数座標」を算出
	blockOriginX := req.MouseRawX - req.OffsetX
	blockOriginY := req.MouseRawY - req.OffsetY

	// 2. 最寄りの格子インデックス（整数）へ丸める（射影）
	estimatedGridX := int(math.Round((blockOriginX - CellSize/2) / CellSize))
	estimatedGridY := int(math.Round((blockOriginY - CellSize/2) / CellSize))

	// 3. 丸めた格子インデックスから、理想的なマスの中心ピクセル座標を逆算
	targetPixelX := float64(estimatedGridX)*CellSize + CellSize/2
	targetPixelY := float64(estimatedGridY)*CellSize + CellSize/2

	// 4. 生の座標と、理想中心座標との間の「ブレ幅（距離）」を測定
	deviationDistance := calculateDistance(blockOriginX, blockOriginY, targetPixelX, targetPixelY)

	response := SnapResultResponse{Success: false, SnappedX: -1, SnappedY: -1}

	// 5. 境界チェックおよび磁気スナップしきい値チェック
	if estimatedGridX >= 0 && estimatedGridX < BoardSize && estimatedGridY >= 0 && estimatedGridY < BoardSize {
		if deviationDistance < SnapTolerance {
			// 吸いつき範囲内！ サーバー側でアライメント成功とみなす
			response.SnappedX = estimatedGridX
			response.SnappedY = estimatedGridY
			response.Success = true
			response.Message = fmt.Sprintf("🧲 偏差 %.2f px でスナップ結合に成功しました。", deviationDistance)
		} else {
			response.Message = fmt.Sprintf("❌ スナップ許容値を超えています（偏差: %.2f px）", deviationDistance)
		}
	} else {
		response.Message = "❌ 盤面の空間領域外にドロップされました。"
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func main() {
	http.HandleFunc("/api/snap-verify", handleSnapVerify)
	fmt.Println("🚀 幾何空間スナップ検証API（Go）がポート :8081 で待機中...")
	http.ListenAndServe(":8081", nil)
}