# ブランチ保護ルール設定ガイド

## 概要

mainブランチへの直接pushを防ぎ、CI/CDパイプラインを経由した安全なデプロイを確保するため、GitHubのブランチ保護ルールを設定することを強く推奨します。

## なぜブランチ保護が必要か

### 問題: mainへの直接push

```bash
# 開発者がmainブランチで直接作業
git checkout main
git add .
git commit -m "Quick fix"
git push origin main  # ← テストをスキップして本番環境へデプロイされる
```

**リスク:**
- ❌ テストが実行されない
- ❌ コードレビューがない
- ❌ Terraform planで変更内容を確認できない
- ❌ 本番環境に問題のあるコードがデプロイされる可能性

### 解決策: ブランチ保護 + Pull Request

```bash
# 正しいフロー
git checkout -b feature/new-feature
git add .
git commit -m "Add new feature"
git push origin feature/new-feature
# ↓ GitHub上でPull Request作成
# ↓ CI実行（test → build → plan）
# ↓ コードレビュー
# ↓ 承認後にmainへマージ
# ↓ Deploy実行（test → build → apply）
```

**メリット:**
- ✅ すべての変更がテストを通過
- ✅ Terraform planで変更内容を事前確認
- ✅ コードレビューによる品質担保
- ✅ デプロイ履歴がPull Requestで追跡可能

## deploy.ymlでのtest実行の意義

`deploy.yml`（mainブランチpush時）でもtestジョブを実行している理由:

### 1. **mainへの直接pushの安全装置**
ブランチ保護ルールが設定されていない、または一時的に無効化された場合でも、最低限のテストを実行します。

### 2. **管理者権限の誤操作対策**
管理者はブランチ保護をバイパスできるため、誤ってmainに直接pushした場合でもテストが実行されます。

### 3. **緊急時の安全性**
緊急時にブランチ保護を一時的に無効化してデプロイする場合でも、テストが実行されます。

**ただし、これは最終手段であり、通常はブランチ保護ルールで直接pushを防ぐべきです。**

## ブランチ保護ルールの設定方法

### Step 1: GitHubリポジトリ設定へ移動

1. GitHubリポジトリのページを開く
2. **Settings** タブをクリック
3. 左サイドバーの **Branches** をクリック
4. **Branch protection rules** セクションで **Add rule** をクリック

### Step 2: 保護ルールの設定

#### 基本設定

| 設定項目 | 値 | 説明 |
|---------|-----|------|
| **Branch name pattern** | `main` | mainブランチを保護 |

#### 必須設定 ✅

以下の設定を有効化してください:

**1. Require a pull request before merging**
- ✅ チェックを入れる
- **Require approvals**: 1以上を推奨（チーム開発の場合）
  - 個人開発の場合は0でも可

**2. Require status checks to pass before merging**
- ✅ チェックを入れる
- **Require branches to be up to date before merging**: ✅ チェック推奨
- **Status checks that are required**: 以下を追加
  ```
  Test
  Build
  Terraform Plan
  ```

**3. Do not allow bypassing the above settings**
- ✅ チェックを入れる（推奨）
- 管理者も含めて全員がルールに従う

#### オプション設定

| 設定項目 | 推奨 | 説明 |
|---------|------|------|
| **Require conversation resolution before merging** | ✅ | レビューコメントの解決を必須化 |
| **Require signed commits** | ⚪ | コミット署名を必須化（任意） |
| **Require linear history** | ⚪ | マージコミットを禁止（任意） |
| **Include administrators** | ✅ | 管理者も保護ルールに従う |
| **Restrict who can push to matching branches** | ⚪ | 特定ユーザーのみpush可能（チーム開発向け） |

### Step 3: ルールの保存

**Create** または **Save changes** をクリックして設定を保存します。

## 設定後の動作確認

### 1. 直接pushのテスト（失敗することを確認）

```bash
git checkout main
echo "test" > test.txt
git add test.txt
git commit -m "Test direct push"
git push origin main
```

**期待される結果:**
```
remote: error: GH006: Protected branch update failed for refs/heads/main.
```

### 2. Pull Requestフローのテスト（成功することを確認）

```bash
git checkout -b feature/test-branch-protection
echo "test" > test.txt
git add test.txt
git commit -m "Test branch protection"
git push origin feature/test-branch-protection
```

GitHub上でPull Requestを作成:
1. **Compare & pull request** をクリック
2. Pull Request作成
3. CI実行を確認（Test → Build → Terraform Plan）
4. Status checksが全て通過することを確認
5. **Merge pull request** が有効になることを確認

## トラブルシューティング

### Status checksが見つからない

**原因:** まだCI/CDワークフローが一度も実行されていない

**解決策:**
1. 一度Pull Requestを作成してCIを実行
2. 実行後、Settings → Branches に戻る
3. Status checksの検索ボックスに `Test`, `Build` などが表示される

### 管理者がルールをバイパスできてしまう

**解決策:**
- **Include administrators** にチェックを入れる
- **Do not allow bypassing the above settings** にチェックを入れる

### 緊急時にデプロイが必要

**対処方法（最終手段）:**
1. Settings → Branches でルールを一時的に無効化
2. デプロイを実行
3. デプロイ後、すぐにルールを再有効化

**より安全な方法:**
- Hotfix用のワークフローを別途作成
- または、管理者承認付きの緊急デプロイフローを用意

## ベストプラクティス

### 推奨設定（チーム開発）

```
✅ Require a pull request before merging
  - Require approvals: 1
✅ Require status checks to pass before merging
  - Require branches to be up to date
  - Status checks: Test, Build, Terraform Plan
✅ Require conversation resolution before merging
✅ Do not allow bypassing the above settings
✅ Include administrators
```

### 推奨設定（個人開発）

```
✅ Require a pull request before merging
  - Require approvals: 0
✅ Require status checks to pass before merging
  - Require branches to be up to date
  - Status checks: Test, Build, Terraform Plan
✅ Do not allow bypassing the above settings
```

## まとめ

| 項目 | 設定なし | 設定あり |
|------|---------|---------|
| **mainへの直接push** | 可能 | **不可能** |
| **テスト実行** | スキップ可能 | **必須** |
| **コードレビュー** | 任意 | **必須**（approvals設定時） |
| **Terraform plan確認** | スキップ可能 | **必須** |
| **デプロイの安全性** | 低い | **高い** |

ブランチ保護ルールを設定することで、CI/CDパイプラインの効果を最大化し、本番環境への安全なデプロイを実現できます。
