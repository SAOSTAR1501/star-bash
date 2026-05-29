# Prompt flow after BE Project setup
echo -e "\n$SEP"
echo -e "${BOLD}${GREEN}✔ Thiết lập Backend Project (Docker) hoàn tất!${NC}"
echo -e "$DASH"
echo -e "${BOLD}${WHITE}💡 GỢI Ý BƯỚC TIẾP THEO (Senior DevOps Flow):${NC}"

echo -e " [1] ${BOLD}→ Vào Project Manager để lấy SSH Private Key add vào GitLab Variables${NC} ${RED}[ĐỀ XUẤT]${NC}"
echo -e " [2] → Xem log / Trạng thái Docker của project mới tạo"
echo -e " [0] → Quay lại Dashboard chính"
echo -e "$DASH"
read -r -p "👉 Nhập lựa chọn của bạn [0-2]: " nc
case "$nc" in
    1|2) NEXT_CHOICE="4" ;;
    *) NEXT_CHOICE="" ;;
esac
