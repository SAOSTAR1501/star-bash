# Prompt flow after GitLab Runner setup
echo -e "\n$SEP"
echo -e "${BOLD}${GREEN}✔ Thiết lập GitLab Runner hoàn thành!${NC}"
echo -e "$DASH"
echo -e "${BOLD}${WHITE}💡 GỢI Ý BƯỚC TIẾP THEO (Senior DevOps Flow):${NC}"

echo -e " [1] ${BOLD}→ Khởi tạo dự án Frontend mới (FE)${NC}"
echo -e " [2] ${BOLD}→ Khởi tạo dự án Backend mới (BE)${NC}"
echo -e " [0] → Quay lại Dashboard chính"
echo -e "$DASH"
read -r -p "👉 Nhập lựa chọn của bạn [0-2]: " nc
case "$nc" in
    1) NEXT_CHOICE="2" ;;
    2) NEXT_CHOICE="3" ;;
    *) NEXT_CHOICE="" ;;
esac
