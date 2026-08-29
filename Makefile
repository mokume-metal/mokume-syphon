# mokume-syphon の開発コマンド。検査の入口は ci-check の 1 つで、CI はそれを呼ぶだけ
# (ローカルと CI の乖離を構造的に不可能にする。mokume の ADR-0001 原則 8)。

.DEFAULT_GOAL := ci-check
.PHONY: setup syphon clean-syphon build test reuse-lint ci-check clean

setup: syphon ## submodule を引き、Syphon.xcframework を焼く
	git submodule update --init --recursive

# SwiftPM は manifest の評価結果を内容ハッシュでキャッシュし、ファイルの出現・消失では
# 無効化しない。焼いた後・消した後は purge-cache で評価し直させる
syphon: ## Syphon.xcframework を手元で焼く (Xcode.app が要る)
	bash scripts/build-syphon.sh
	swift package purge-cache

clean-syphon: ## 手元の成果物を捨て、Release の資産側 (利用者と同じ経路) に戻す
	rm -rf Frameworks
	swift package purge-cache

build:
	swift build

test:
	swift test

# **submodule も見る。** 再配布する第三者の素材は Vendor/ の中にしか無いので、
# 既定の「submodule は飛ばす」のままだと、帰属の検査が一番見るべきものを見ない
reuse-lint:
	reuse --include-submodules lint

ci-check: build test reuse-lint ## CI と同一の検査 — push 前に通す

clean:
	rm -rf .build
